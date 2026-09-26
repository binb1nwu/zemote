import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../link/device_link.dart';
import '../rpc/channel_client.dart';
import '../rpc/socket_protocol.dart';
import '../zcode/server_info.dart';
import 'ws_connect.dart';

enum ConnectionPhase {
  /// Not started or explicitly closed.
  idle,
  connecting,
  online,

  /// Lost or failed; a retry is scheduled.
  offline,

  /// The server rejected the token (`zcode --web` prints a new token on every
  /// start unless `--token` is given). No automatic retry.
  unauthorized,
}

@immutable
class ConnectionStatus {
  const ConnectionStatus(this.phase,
      {this.error, this.attempt = 0, this.nextRetryAt, this.latencyMs});

  final ConnectionPhase phase;
  final String? error;
  final int attempt;
  final DateTime? nextRetryAt;
  final int? latencyMs;

  bool get isOnline => phase == ConnectionPhase.online;
}

/// One live WebSocket RPC connection to a ZCode Web server, with automatic
/// reconnect.
///
/// Every successful (re)connect creates a fresh [ChannelClient] and bumps
/// [generation]; stores listen to [onOnline] and re-subscribe on the new
/// client (ZCode subscriptions are per connection).
class DeviceConnection {
  DeviceConnection(this.link, {this.log});

  final DeviceLink link;
  final void Function(String line)? log;

  static const _retryDelays = [1, 2, 4, 8, 15];

  final ValueNotifier<ConnectionStatus> status =
      ValueNotifier(const ConnectionStatus(ConnectionPhase.idle));
  final StreamController<ChannelClient> _online =
      StreamController<ChannelClient>.broadcast();

  /// Fires with the new client every time the connection becomes usable.
  Stream<ChannelClient> get onOnline => _online.stream;

  ServerInfo? serverInfo;
  ChannelClient? _client;
  WebSocketChannel? _socket;
  StreamSubscription? _socketSub;
  Timer? _retryTimer;
  int _attempt = 0;
  int generation = 0;
  bool _started = false;
  Future<void>? _connecting;

  ChannelClient? get client => status.value.isOnline ? _client : null;

  /// Returns the connected client, waiting for the next connect if needed.
  Future<ChannelClient> requireClient(
      {Duration timeout = const Duration(seconds: 20)}) async {
    final current = client;
    if (current != null) return current;
    if (status.value.phase == ConnectionPhase.unauthorized) {
      throw const ConnectionClosedError('unauthorized');
    }
    start();
    return onOnline.first.timeout(timeout);
  }

  void start() {
    _started = true;
    if (status.value.phase == ConnectionPhase.online && _client != null) return;
    _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  /// Retry right away (app resumed, network changed, user tapped retry).
  void reconnectNow() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    _started = true;
    start();
  }

  /// Drops the current socket and connects again right away.
  void forceReconnect() {
    _drop('manual reconnect');
    _connecting = null;
    reconnectNow();
  }

  /// Cheap liveness probe used when the app returns to the foreground: a
  /// socket that sat through a network change can look open but be dead.
  Future<void> verifyAlive() async {
    final c = client;
    if (c == null) {
      reconnectNow();
      return;
    }
    final sw = Stopwatch()..start();
    try {
      await c.call<Object?>('zcode-agent', 'helloConversationV4', const [],
          const Duration(seconds: 5));
      status.value = ConnectionStatus(ConnectionPhase.online,
          latencyMs: sw.elapsedMilliseconds);
    } catch (e) {
      _log('liveness check failed: $e');
      _drop('liveness check failed');
      reconnectNow();
    }
  }

  Future<void> _connect() async {
    _retryTimer?.cancel();
    status.value =
        ConnectionStatus(ConnectionPhase.connecting, attempt: _attempt);
    try {
      serverInfo = await _fetchServerInfo();
      final uri = link.webSocketUri;
      _log('connect ${link.displayHost}');
      final socket = connectWebSocket(uri);
      final reader = SocketFrameReader();
      final client = ChannelClient((body) {
        try {
          socket.sink.add(SocketFrame.encode(body));
        } catch (_) {}
      });
      final myGeneration = ++generation;
      // Listen before `ready` resolves: the server sends `Initialize` right
      // after the upgrade and it must not be dropped.
      _socketSub = socket.stream.listen(
        (data) {
          final bytes = data is Uint8List
              ? data
              : data is List<int>
                  ? Uint8List.fromList(data)
                  : null;
          if (bytes == null) return;
          for (final message in reader.accept(bytes)) {
            client.acceptMessage(message);
          }
        },
        onError: (Object e) => _onSocketClosed(myGeneration, '$e'),
        onDone: () => _onSocketClosed(
            myGeneration, socket.closeReason ?? 'closed (${socket.closeCode})'),
        cancelOnError: true,
      );
      _socket = socket;
      _client = client;
      final sw = Stopwatch()..start();
      await socket.ready.timeout(const Duration(seconds: 12));
      await client.initialized.timeout(const Duration(seconds: 12));
      if (myGeneration != generation) return;
      _attempt = 0;
      status.value = ConnectionStatus(ConnectionPhase.online,
          latencyMs: sw.elapsedMilliseconds);
      _log('online (${sw.elapsedMilliseconds}ms)');
      _online.add(client);
    } on UnauthorizedError catch (e) {
      _drop('$e');
      status.value =
          ConnectionStatus(ConnectionPhase.unauthorized, error: e.message);
    } catch (e) {
      _drop('$e');
      _scheduleRetry(_describe(e));
    }
  }

  Future<ServerInfo?> _fetchServerInfo() async {
    try {
      final res = await http
          .get(link.serverInfoUri)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) {
        throw const UnauthorizedError('token rejected');
      }
      if (res.statusCode != 200) {
        throw HttpStatusError(res.statusCode);
      }
      return ServerInfo.fromJson(
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } on UnauthorizedError {
      rethrow;
    } on HttpStatusError {
      rethrow;
    } catch (e) {
      // Browsers block this cross-origin request (the server sends no CORS
      // headers) while still allowing the WebSocket. Keep going there.
      if (kIsWeb) return serverInfo;
      rethrow;
    }
  }

  void _onSocketClosed(int socketGeneration, String reason) {
    if (socketGeneration != generation) return;
    _log('socket closed: $reason');
    _drop(reason);
    if (!_started) {
      status.value = const ConnectionStatus(ConnectionPhase.idle);
      return;
    }
    _scheduleRetry(reason);
  }

  void _drop(String reason) {
    generation++;
    _socketSub?.cancel();
    _socketSub = null;
    _client?.dispose(ConnectionClosedError(reason));
    _client = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
  }

  void _scheduleRetry(String error) {
    if (!_started) return;
    final seconds = _retryDelays[_attempt.clamp(0, _retryDelays.length - 1)];
    _attempt++;
    final at = DateTime.now().add(Duration(seconds: seconds));
    status.value = ConnectionStatus(ConnectionPhase.offline,
        error: error, attempt: _attempt, nextRetryAt: at);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), start);
  }

  String _describe(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is HttpStatusError) return 'HTTP ${e.status}';
    final text = '$e';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  void _log(String line) => log?.call('[conn ${link.displayHost}] $line');

  void close() {
    _started = false;
    _retryTimer?.cancel();
    _drop('closed');
    status.value = const ConnectionStatus(ConnectionPhase.idle);
  }

  void dispose() {
    close();
    _online.close();
    status.dispose();
  }
}

class UnauthorizedError implements Exception {
  const UnauthorizedError(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpStatusError implements Exception {
  const HttpStatusError(this.status);
  final int status;
  @override
  String toString() => 'HTTP $status';
}
