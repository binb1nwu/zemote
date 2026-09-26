import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/connection/device_connection.dart';
import '../core/rpc/channel_client.dart';
import '../core/v4/conversation_store.dart';
import '../core/v4/ids.dart';
import '../core/v4/sessions_index_store.dart';
import '../core/v4/synced_topic.dart';
import '../core/v4/topic_router.dart';
import '../core/zcode/server_info.dart';
import '../core/zcode/zcode_api.dart';
import 'device_registry.dart';
import 'log_store.dart';
import 'model_catalog.dart';
import 'task_list_store.dart';

/// Runtime of one linked device: its connection, API, model catalog and the
/// open workspace(s). Devices stay connected in the background so switching
/// between them is instant.
class DeviceSession extends ChangeNotifier {
  DeviceSession(this.device, {required this.clientId, required this.appVersion, required this.logs})
      : connection = DeviceConnection(device.link, log: logs.add) {
    connection.status.addListener(_onStatus);
    _onlineSub = connection.onOnline.listen(_onOnline);
  }

  final Device device;
  final String clientId;
  final String appVersion;
  final LogStore logs;
  DeviceConnection connection;
  late StreamSubscription<ChannelClient> _onlineSub;

  ZCodeApi? api;
  final StreamController<ZCodeApi> _apiController = StreamController.broadcast();
  Stream<ZCodeApi> get onApi => _apiController.stream;

  ModelCatalog models = const ModelCatalog();
  StreamSubscription? _modelSub;

  final Map<String, WorkspaceSession> _workspaces = {};
  WorkspaceSession? _current;
  WorkspaceSession? get workspace => _current;

  ConnectionStatus get status => connection.status.value;

  List<WorkspaceRef> get workspaces {
    final fromServer = connection.serverInfo?.workspaces ?? const [];
    if (fromServer.isNotEmpty) return fromServer;
    final last = device.lastWorkspacePath;
    return last == null ? const [] : [WorkspaceRef(path: last, label: _basename(last))];
  }

  String get displayName {
    final label = device.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    final info = connection.serverInfo;
    if (info != null && info.displayName.isNotEmpty) return info.displayName;
    return device.link.displayHost;
  }

  /// Aggregated count of tasks that need attention (running / waiting).
  int get activeTaskCount {
    var n = 0;
    for (final ws in _workspaces.values) {
      for (final s in ws.sessionsIndex.sessions.values) {
        final phase = s['phase'];
        if (phase == 'running' || phase == 'prewarming' || s['pendingInteraction'] != null) n++;
      }
    }
    return n;
  }

  void start() => connection.start();

  /// Replaces the link (new token) and reconnects.
  void relink() {
    connection.status.removeListener(_onStatus);
    _onlineSub.cancel();
    connection.dispose();
    connection = DeviceConnection(device.link, log: logs.add);
    connection.status.addListener(_onStatus);
    _onlineSub = connection.onOnline.listen(_onOnline);
    _markOffline();
    connection.start();
    notifyListeners();
  }

  void _onStatus() {
    if (!connection.status.value.isOnline && api != null) _markOffline();
    notifyListeners();
  }

  void _markOffline() {
    api = null;
    _modelSub?.cancel();
    for (final ws in _workspaces.values) {
      ws._markOffline();
    }
  }

  Future<void> _onOnline(ChannelClient client) async {
    final next = ZCodeApi(client, clientId: clientId, appVersion: appVersion);
    api = next;
    for (final ws in _workspaces.values) {
      ws._attach(next);
    }
    // Existing topics re-subscribe on this event. Workspaces created below
    // subscribe directly (a broadcast event only reaches current listeners).
    _apiController.add(next);
    final list = workspaces;
    if (_current == null && list.isNotEmpty) {
      final last = device.lastWorkspacePath;
      _current = _workspaceFor(list.firstWhere((w) => w.path == last, orElse: () => list.first));
    }
    unawaited(_loadModels(next));
    notifyListeners();
  }

  Future<void> _loadModels(ZCodeApi api) async {
    try {
      models = ModelCatalog.fromView(await api.modelSelectionView());
      notifyListeners();
      _modelSub?.cancel();
      _modelSub = api.modelSelectionChanges().listen((view) {
        if (view is Map<String, dynamic>) {
          models = ModelCatalog.fromView(view);
          notifyListeners();
        }
      });
    } catch (e) {
      logs.add('[models] $e');
    }
  }

  WorkspaceSession _workspaceFor(WorkspaceRef ref) {
    return _workspaces.putIfAbsent(ref.key, () {
      final ws = WorkspaceSession(this, ref);
      if (api != null) ws._attach(api!);
      ws._start();
      return ws;
    });
  }

  void selectWorkspace(WorkspaceRef ref) {
    _current = _workspaceFor(ref);
    notifyListeners();
  }

  @override
  void dispose() {
    connection.status.removeListener(_onStatus);
    _onlineSub.cancel();
    _modelSub?.cancel();
    for (final ws in _workspaces.values) {
      ws._dispose();
    }
    _workspaces.clear();
    connection.dispose();
    _apiController.close();
    super.dispose();
  }
}

/// One workspace of a device: its topic router, live session list, task list
/// and a small cache of open conversations.
class WorkspaceSession implements WorkspaceContext {
  WorkspaceSession(this.device, this.workspace) : router = TopicRouter(workspace) {
    sessionsIndex = SessionsIndexStore(this);
    tasks = TaskListStore(this, sessionsIndex);
  }

  final DeviceSession device;
  @override
  final WorkspaceRef workspace;
  @override
  final TopicRouter router;
  late final SessionsIndexStore sessionsIndex;
  late final TaskListStore tasks;

  static const _keepConversations = 4;
  final Map<String, ConversationStore> _conversations = {};
  final List<StreamSubscription> _subs = [];
  int _runtimeGeneration = 0;

  @override
  ZCodeApi? get api => device.api;

  @override
  Stream<ZCodeApi> get onApi => device.onApi;

  @override
  void log(String line) => device.logs.add('[${device.device.link.displayHost}] $line');

  void _start() {
    sessionsIndex.start();
    if (api != null) tasks.refresh();
  }

  void _attach(ZCodeApi api) {
    router.attach(api);
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..add(api.workspaceEvents(workspace).listen((event) {
        if (event['type'] == 'workspace_task_list_changed') tasks.scheduleRefresh();
      }))
      ..add(api.runtimeLifecycle().listen((event) {
        if (event['workspaceKey'] != workspace.key) return;
        // Agent process restarted: its V4 subscriptions are gone.
        if (event['state'] == 'available' && _runtimeGeneration++ > 0) {
          sessionsIndex.refresh();
          for (final c in _conversations.values) {
            c.refresh();
          }
        }
      }));
    tasks.scheduleRefresh(Duration.zero);
  }

  void _markOffline() {
    router.detach();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    sessionsIndex.markOffline();
    for (final c in _conversations.values) {
      c.markOffline();
    }
  }

  /// Returns the (cached) live projection of a conversation.
  ConversationStore conversation(String sessionId) {
    final existing = _conversations.remove(sessionId);
    if (existing != null) {
      _conversations[sessionId] = existing; // most recently used last
      return existing;
    }
    final store = ConversationStore(this, sessionId)..start();
    _conversations[sessionId] = store;
    while (_conversations.length > _keepConversations) {
      final oldest = _conversations.keys.first;
      _conversations.remove(oldest)?.dispose();
    }
    return store;
  }

  /// Creates a task with its first message (`createSession` + `firstInput`).
  Future<String> createTask(String text,
      {ModelSelection? model, String? mode, bool? planEnabled}) async {
    final api = this.api;
    if (api == null) throw const ConnectionClosedError('offline');
    final envelope = <String, Object?>{
      'commandId': uuidv7(),
      'clientId': api.clientId,
      'sessionId': null,
      'type': 'createSession',
      'payload': {
        'workspaceId': workspace.key,
        'firstInput': {
          'text': text,
          if (model != null) 'modelSelection': model.toJson(),
          if (mode != null) 'mode': mode,
          if (planEnabled != null) 'planEnabled': planEnabled,
        },
        if (model != null || mode != null)
          'config': {
            if (model != null) 'modelSelection': model.toJson(),
            if (mode != null) 'mode': mode,
          },
      },
      'issuedAt': DateTime.now().millisecondsSinceEpoch,
    };
    final ack = await api.sendCommand(workspace, envelope);
    if (ack['status'] != 'accepted' && ack['status'] != 'duplicate') {
      throw CommandRejected('${ack['status']}', ack['reasonCode'] as String?, ack['message'] as String?);
    }
    final result = ack['result'];
    final sessionId = result is Map ? result['sessionId'] as String? : null;
    if (sessionId == null) throw CommandRejected('failed', null, 'createSession returned no sessionId');
    tasks.scheduleRefresh(const Duration(milliseconds: 300));
    return sessionId;
  }

  void _dispose() {
    _markOffline();
    for (final c in _conversations.values) {
      c.dispose();
    }
    _conversations.clear();
    tasks.dispose();
    sessionsIndex.dispose();
    router.dispose();
  }
}

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Topic status helper for UI badges.
extension TopicStatusX on TopicStatus {
  bool get isSyncing => this == TopicStatus.connecting || this == TopicStatus.recovering;
}
