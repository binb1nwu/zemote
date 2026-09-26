import 'dart:async';

import '../rpc/channel_client.dart';
import 'server_info.dart';

/// Typed facade over the ZCode services exposed on `/ws`
/// (`IZCodeAgentService`, `IZCodeTaskService`, `IModelSelectionService`).
///
/// Method names and parameter shapes follow `packages/services` in ZCode;
/// every service method takes its arguments as a list.
class ZCodeApi {
  ZCodeApi(this.client, {required this.clientId, required this.appVersion});

  final ChannelClient client;
  final String clientId;
  final String appVersion;

  static const agent = 'zcode-agent';
  static const task = 'zcode-task';
  static const modelSelection = 'model-selection';

  static const _rpcTimeout = Duration(seconds: 30);

  static final Expando<Future<Map<String, dynamic>>> _handshakes = Expando();

  Future<T> _call<T>(String channel, String method, [List<Object?> args = const []]) =>
      client.call<T>(channel, method, args, _rpcTimeout);

  // ── V4 connection handshake ──

  /// `hello` + `clientHello`, once per connection (see
  /// `agentV4ConnectionHandshake.ts`).
  Future<Map<String, dynamic>> ensureHandshake() {
    return _handshakes[client] ??= () async {
      final hello = Map<String, dynamic>.from(
          await _call<Map>(agent, 'helloConversationV4'));
      await _call<Object?>(agent, 'initializeConversationV4', [
        {
          'kind': 'clientHello',
          'protocolVersion': hello['protocolVersion'] ?? 3,
          'clientId': clientId,
          'clientKind': 'mobileApp',
          'appVersion': appVersion,
        }
      ]);
      return hello;
    }()
      ..catchError((Object _) {
        _handshakes[client] = null;
        return <String, dynamic>{};
      });
  }

  // ── conversation topic ──

  Future<Map<String, dynamic>> subscribeConversation(
    WorkspaceRef ws,
    String sessionId, {
    Map<String, Object?>? base,
  }) async {
    await ensureHandshake();
    final res = await _call<Map>(agent, 'subscribeConversationV4', [
      {
        ...ws.target,
        'sessionId': sessionId,
        if (base != null) 'base': base,
        'visibility': 'foreground',
      }
    ]);
    return Map<String, dynamic>.from(res['ack'] as Map);
  }

  Future<Map<String, dynamic>> resyncConversation(
    WorkspaceRef ws,
    String subscriptionId, {
    Map<String, Object?>? base,
    bool forceSnapshot = false,
  }) async {
    await ensureHandshake();
    final res = await _call<Map>(agent, 'resyncConversationV4', [
      {
        ...ws.target,
        'subscriptionId': subscriptionId,
        'base': base,
        if (forceSnapshot) 'forceSnapshot': true,
      }
    ]);
    return Map<String, dynamic>.from(res['ack'] as Map);
  }

  Future<void> unsubscribeConversation(WorkspaceRef ws, String subscriptionId) =>
      _call<Object?>(agent, 'unsubscribeConversationV4', [
        {...ws.target, 'subscriptionId': subscriptionId}
      ]);

  /// Older rows (`rowId < beforeRowId`), ascending.
  Future<Map<String, dynamic>> rowsRange(
    WorkspaceRef ws,
    String sessionId, {
    int? beforeRowId,
    int limit = 80,
  }) async =>
      Map<String, dynamic>.from(await _call<Map>(agent, 'conversationRowsRangeV4', [
        {
          ...ws.target,
          'sessionId': sessionId,
          if (beforeRowId != null) 'beforeRowId': beforeRowId,
          'limit': limit,
        }
      ]));

  Future<Map<String, dynamic>> fileChanges(WorkspaceRef ws, String sessionId,
          {Map<String, Object?> extra = const {}}) async =>
      Map<String, dynamic>.from(await _call<Map>(agent, 'conversationFileChangesV4', [
        {...ws.target, 'sessionId': sessionId, ...extra}
      ]));

  /// Sends a V4 command envelope and returns its `CommandAck`.
  Future<Map<String, dynamic>> sendCommand(
      WorkspaceRef ws, Map<String, Object?> envelope) async {
    await ensureHandshake();
    return Map<String, dynamic>.from(await client.call<Map>(
      agent,
      'sendConversationCommandV4',
      [
        {...ws.target, 'envelope': envelope}
      ],
      const Duration(seconds: 90),
    ));
  }

  Stream<Map<String, dynamic>> conversationFrames(WorkspaceRef ws) => client
      .listen(agent, 'onDynamicConversationFrame', ws.target)
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  // ── sessions-index topic ──

  Future<Map<String, dynamic>> subscribeSessionsIndex(WorkspaceRef ws,
      {Map<String, Object?>? base}) async {
    await ensureHandshake();
    final res = await _call<Map>(agent, 'subscribeSessionsIndexV4', [
      {
        ...ws.target,
        if (base != null) 'base': base,
        'visibility': 'foreground',
      }
    ]);
    return Map<String, dynamic>.from(res['ack'] as Map);
  }

  Future<Map<String, dynamic>> resyncSessionsIndex(
    WorkspaceRef ws,
    String subscriptionId, {
    Map<String, Object?>? base,
    bool forceSnapshot = false,
  }) async {
    final res = await _call<Map>(agent, 'resyncSessionsIndexV4', [
      {
        ...ws.target,
        'subscriptionId': subscriptionId,
        'base': base,
        if (forceSnapshot) 'forceSnapshot': true,
      }
    ]);
    return Map<String, dynamic>.from(res['ack'] as Map);
  }

  Future<void> unsubscribeSessionsIndex(WorkspaceRef ws, String subscriptionId) =>
      _call<Object?>(agent, 'unsubscribeSessionsIndexV4', [
        {...ws.target, 'subscriptionId': subscriptionId}
      ]);

  Stream<Map<String, dynamic>> sessionsIndexFrames(WorkspaceRef ws) => client
      .listen(agent, 'onDynamicSessionsIndexFrame', ws.target)
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// `{workspaceKey, state: available|unavailable}` agent runtime transitions.
  Stream<Map<String, dynamic>> runtimeLifecycle() => client
      .listen(agent, 'onAgentRuntimeLifecycle')
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  // ── tasks-index (persistent list membership) ──

  Future<List<Map<String, dynamic>>> _list(String method, WorkspaceRef ws) async {
    final res = await _call<List>(task, method, [ws.target]);
    return [for (final e in res) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<List<Map<String, dynamic>>> listTasks(WorkspaceRef ws) => _list('listTasks', ws);
  Future<List<Map<String, dynamic>>> listPinnedTasks(WorkspaceRef ws) =>
      _list('listPinnedTasks', ws);
  Future<List<Map<String, dynamic>>> listArchivedTasks(WorkspaceRef ws) =>
      _list('listArchivedTasks', ws);

  Future<List<String>> listDeletedTaskIds(WorkspaceRef ws) async {
    final res = await _call<List>(task, 'listDeletedTaskIds', [ws.target]);
    return [for (final e in res) '$e'];
  }

  Future<void> setTaskPinned(WorkspaceRef ws, String taskId, bool pinned) =>
      _call<Object?>(task, 'setTaskPinned', [
        {...ws.target, 'taskId': taskId, 'pinned': pinned}
      ]);

  Future<void> archiveTask(WorkspaceRef ws, String taskId) =>
      _call<Object?>(task, 'archiveTask', [
        {...ws.target, 'taskId': taskId}
      ]);

  Future<void> unarchiveTask(WorkspaceRef ws, String taskId) =>
      _call<Object?>(task, 'unarchiveTask', [
        {...ws.target, 'taskId': taskId}
      ]);

  Future<void> deleteTask(WorkspaceRef ws, String taskId) =>
      _call<Object?>(task, 'deleteTask', [
        {...ws.target, 'taskId': taskId}
      ]);

  Future<void> setTaskUnread(WorkspaceRef ws, String taskId, bool unread) =>
      _call<Object?>(task, 'setTaskUnread', [
        {...ws.target, 'taskId': taskId, 'unread': unread}
      ]);

  /// `workspace_task_list_changed`, `workspace_slash_commands_update`, …
  Stream<Map<String, dynamic>> workspaceEvents(WorkspaceRef ws) => client
      .listen(task, 'onDynamicWorkspaceEvent', ws.target)
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  // ── models ──

  Future<Map<String, dynamic>> modelSelectionView() async =>
      Map<String, dynamic>.from(await _call<Map>(modelSelection, 'getView'));

  Stream<Object?> modelSelectionChanges() => client.listen(modelSelection, 'onDidChange');
}
