/// A ZCode Web link as printed by `zcode --web`, e.g.
/// `http://192.168.1.8:3030/?token=AbC…`.
///
/// The server authenticates `/api/*` and `/ws` with the `token` query
/// parameter (or the `zcode_lite_token` cookie it sets), see
/// `packages/server/src/http.ts` in ZCode.
class DeviceLink {
  const DeviceLink._(this.base, this.token);

  /// Origin plus the directory the Web UI is served from, always ending in `/`.
  final Uri base;
  final String? token;

  static DeviceLink? tryParse(String raw) {
    final result = parse(raw);
    return result.link;
  }

  static DeviceLinkParseResult parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return const DeviceLinkParseResult.error('empty');
    // Links copied from terminals sometimes carry a trailing punctuation.
    text = text.replaceAll(RegExp(r'[\s"<>]+$'), '');
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      text = 'http://$text';
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return const DeviceLinkParseResult.error('invalid');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const DeviceLinkParseResult.error('invalid');
    }
    if (uri.host.isEmpty) return const DeviceLinkParseResult.error('invalid');
    if (uri.queryParameters.containsKey('sid') &&
        uri.queryParameters.containsKey('hash')) {
      return const DeviceLinkParseResult.error('legacyRelay');
    }
    final token = uri.queryParameters['token']?.trim();
    var path = uri.path;
    if (path.isEmpty || !path.endsWith('/')) {
      final slash = path.lastIndexOf('/');
      path = slash < 0 ? '/' : path.substring(0, slash + 1);
    }
    final base = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
    return DeviceLinkParseResult.ok(
        DeviceLink._(base, token == null || token.isEmpty ? null : token));
  }

  Map<String, String> get _auth => token == null ? const {} : {'token': token!};

  Uri get serverInfoUri =>
      base.resolve('api/server-info').replace(queryParameters: _auth.isEmpty ? null : _auth);

  Uri get webSocketUri {
    final ws = base.resolve('ws');
    return ws.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: _auth.isEmpty ? null : _auth,
    );
  }

  /// The link in canonical form (what gets stored).
  String get canonical =>
      (token == null ? base : base.replace(queryParameters: _auth)).toString();

  /// Host and port for display, e.g. `192.168.1.8:3030`.
  String get displayHost => base.hasPort ? '${base.host}:${base.port}' : base.host;

  @override
  bool operator ==(Object other) =>
      other is DeviceLink && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;
}

class DeviceLinkParseResult {
  const DeviceLinkParseResult.ok(DeviceLink this.link) : error = null;
  const DeviceLinkParseResult.error(String this.error) : link = null;

  final DeviceLink? link;

  /// `empty`, `invalid` or `legacyRelay`.
  final String? error;
}
