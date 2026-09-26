/// `/api/server-info` of a ZCode Web server (`ServerRemoteInfo`).
class ServerInfo {
  const ServerInfo({
    required this.serverId,
    this.name,
    this.version,
    this.workspaces = const [],
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        serverId: '${json['serverId'] ?? ''}',
        name: json['name'] as String?,
        version: json['version'] as String?,
        workspaces: [
          for (final w in (json['workspaces'] as List? ?? const []))
            if (w is Map && w['path'] is String)
              WorkspaceRef(
                path: w['path'] as String,
                label: (w['label'] as String?) ?? _basename(w['path'] as String),
                identity: w['workspaceIdentity'] as String?,
              ),
        ],
      );

  final String serverId;
  final String? name;
  final String? version;
  final List<WorkspaceRef> workspaces;

  /// Best human readable device name.
  String get displayName => (name?.trim().isNotEmpty ?? false) ? name!.trim() : serverId;
}

class WorkspaceRef {
  const WorkspaceRef({required this.path, required this.label, this.identity});

  final String path;
  final String label;
  final String? identity;

  /// `workspaceKey` in ZCode: identity for remote workspaces, else the path.
  String get key => (identity?.trim().isNotEmpty ?? false) ? identity!.trim() : path;

  /// `ZCodeAgentWorkspaceTarget` parameters.
  Map<String, Object?> get target => {
        'workspacePath': path,
        if (identity?.trim().isNotEmpty ?? false) 'workspaceIdentity': identity,
      };

  @override
  bool operator ==(Object other) => other is WorkspaceRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
