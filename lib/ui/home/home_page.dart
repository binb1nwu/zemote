import 'package:flutter/material.dart';

import '../../core/connection/device_connection.dart';
import '../../state/app_state.dart';
import '../../state/device_session.dart';
import '../conversation/conversation_view.dart';
import '../conversation/new_task_view.dart';
import '../devices/add_device_page.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'sidebar.dart';

/// Responsive shell: phones get ZCode's single column + drawer presentation,
/// tablets/desktops a persistent sidebar next to the conversation.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.app});
  final AppState app;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey();

  /// Selected task per `device|workspace`; null = new task screen.
  final Map<String, String?> _selection = {};

  AppState get app => widget.app;

  String? _selKey(DeviceSession d) {
    final ws = d.workspace;
    return ws == null ? null : '${d.device.id}|${ws.workspace.key}';
  }

  String? _selected(DeviceSession? d) {
    if (d == null) return null;
    final key = _selKey(d);
    return key == null ? null : _selection[key];
  }

  void _select(DeviceSession d, String? taskId, {bool closeDrawer = true}) {
    final key = _selKey(d);
    if (key == null) return;
    setState(() => _selection[key] = taskId);
    if (d.workspace != null) app.registry.rememberWorkspace(d.device, d.workspace!.workspace.path);
    if (closeDrawer && (_scaffold.currentState?.isDrawerOpen ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.registry]),
      builder: (context, _) {
        final device = app.activeSession;
        return ListenableBuilder(
          listenable: device ?? app,
          builder: (context, _) => _build(context, device),
        );
      },
    );
  }

  Widget _build(BuildContext context, DeviceSession? device) {
    final z = context.z;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = Sidebar(
      app: app,
      device: device,
      selectedTaskId: _selected(device),
      onSelectTask: (id) => _select(device!, id),
      onNewTask: () => _select(device!, null),
    );
    final content = Column(children: [
      _Header(
        app: app,
        device: device,
        taskId: _selected(device),
        showMenu: !wide,
        onMenu: () => _scaffold.currentState?.openDrawer(),
        onNewTask: device == null ? null : () => _select(device, null, closeDrawer: false),
      ),
      Expanded(child: _body(context, device)),
    ]);
    if (wide) {
      return Scaffold(
        key: _scaffold,
        backgroundColor: z.sidebar,
        body: Row(children: [
          SizedBox(width: 300, child: sidebar),
          Expanded(
            child: SafeArea(
              left: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                decoration: BoxDecoration(
                  color: z.background,
                  borderRadius: BorderRadius.circular(ZRadius.xl),
                  border: Border.all(color: z.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: content,
              ),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      key: _scaffold,
      backgroundColor: z.background,
      drawer: Drawer(width: MediaQuery.sizeOf(context).width * 0.86, child: sidebar),
      body: SafeArea(bottom: false, child: content),
    );
  }

  Widget _body(BuildContext context, DeviceSession? device) {
    final s = S.of(context);
    final z = context.z;
    if (device == null) {
      return _EmptyState(
        icon: Icons.devices_other_rounded,
        title: s.noDevices,
        body: s.noDevicesHint,
        action: FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddDevicePage(app: app))),
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.addDevice),
        ),
      );
    }
    final status = device.status;
    if (status.phase == ConnectionPhase.unauthorized) {
      return _EmptyState(
        icon: Icons.key_off_rounded,
        title: s.unauthorized,
        body: s.unauthorizedHint,
        action: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddDevicePage(app: app, device: device.device))),
          child: Text(s.updateLink),
        ),
      );
    }
    final ws = device.workspace;
    if (ws == null) {
      return _EmptyState(
        icon: Icons.computer_rounded,
        title: device.displayName,
        body: '${connectionLabel(context, status)}\n${device.device.link.displayHost}'
            '${status.error == null ? '' : '\n${status.error}'}',
        leading: status.phase == ConnectionPhase.connecting ? const ZSpinner(size: 18) : null,
        action: OutlinedButton(onPressed: device.connection.reconnectNow, child: Text(s.retry)),
        bodyColor: z.foregroundSubtle,
      );
    }
    final taskId = _selected(device);
    if (taskId == null) {
      return NewTaskView(
        key: ValueKey('new-${device.device.id}-${ws.workspace.key}'),
        device: device,
        workspace: ws,
        onCreated: (id) => _select(device, id, closeDrawer: false),
      );
    }
    return ConversationView(
      key: ValueKey('conv-${device.device.id}-${ws.workspace.key}'),
      device: device,
      workspace: ws,
      sessionId: taskId,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.device,
    required this.taskId,
    required this.showMenu,
    required this.onMenu,
    required this.onNewTask,
  });

  final AppState app;
  final DeviceSession? device;
  final String? taskId;
  final bool showMenu;
  final VoidCallback onMenu;
  final VoidCallback? onNewTask;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final d = device;
    final ws = d?.workspace;
    Widget title;
    if (ws != null && taskId != null) {
      title = ListenableBuilder(
        listenable: ws.tasks,
        builder: (context, _) {
          final item = ws.tasks.find(taskId!);
          final text = item?.title.trim().isNotEmpty ?? false
              ? item!.title
              : ws.conversation(taskId!).title;
          return _titleText(context, text.isEmpty ? s.newTask : text);
        },
      );
    } else {
      title = _titleText(context, d == null ? s.appName : s.newTask);
    }
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: z.border))),
      child: Row(children: [
        if (showMenu)
          _MenuButton(device: d, onTap: onMenu)
        else
          const SizedBox(width: 8),
        const SizedBox(width: 4),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            title,
            if (d != null)
              Row(children: [
                StatusDot(color: connectionColor(context, d.status.phase), size: 6),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    [d.displayName, if (ws != null) ws.workspace.label].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: ZText.xs, color: z.foregroundSubtle),
                  ),
                ),
              ]),
          ]),
        ),
        if (ws != null && taskId != null) _TaskMenu(workspace: ws, taskId: taskId!),
        if (onNewTask != null && taskId != null)
          ZIconButton(icon: Icons.add_comment_outlined, tooltip: s.newTask, onPressed: onNewTask),
      ]),
    );
  }

  Widget _titleText(BuildContext context, String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: ZText.base, fontWeight: FontWeight.w600, color: context.z.foreground),
      );
}

/// Drawer button with a badge when another device has running / waiting tasks.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.device, required this.onTap});
  final DeviceSession? device;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ZIconButton(icon: Icons.menu_rounded, iconSize: 20, onPressed: onTap);
  }
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.workspace, required this.taskId});
  final WorkspaceSession workspace;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ZIconButton(
      icon: Icons.more_horiz,
      onPressed: () {
        final item = workspace.tasks.find(taskId);
        final store = workspace.conversation(taskId);
        Future<void> run(Future<void> Function() op) async {
          try {
            await op();
          } catch (e) {
            if (context.mounted) showToast(context, '$e');
          }
        }

        showZSheet<void>(context, title: item?.title, builder: (ctx) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ZMenuItem(
              icon: Icons.edit_outlined,
              title: s.rename,
              onTap: () async {
                Navigator.pop(ctx);
                final controller = TextEditingController(text: item?.title ?? store.title);
                final name = await showDialog<String>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(s.rename),
                    content: TextField(controller: controller, autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx), child: Text(s.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(dctx, controller.text), child: Text(s.save)),
                    ],
                  ),
                );
                if (name != null && name.trim().isNotEmpty) {
                  await run(() => store.rename(name.trim()));
                  workspace.tasks.scheduleRefresh();
                }
              },
            ),
            if (item != null)
              ZMenuItem(
                icon: item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                title: item.pinned ? s.unpin : s.pin,
                onTap: () {
                  Navigator.pop(ctx);
                  run(() => workspace.tasks.setPinned(taskId, !item.pinned));
                },
              ),
            if (item != null)
              ZMenuItem(
                icon: item.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                title: item.archived ? s.unarchive : s.archive,
                onTap: () {
                  Navigator.pop(ctx);
                  run(() => workspace.tasks.setArchived(taskId, !item.archived));
                },
              ),
            ZMenuItem(
              icon: Icons.compress_rounded,
              title: s.compact,
              onTap: () {
                Navigator.pop(ctx);
                run(store.compact);
              },
            ),
            ZMenuItem(
              icon: Icons.sync_rounded,
              title: s.reconnect,
              onTap: () {
                Navigator.pop(ctx);
                store.refresh();
              },
            ),
          ]);
        });
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.leading,
    this.bodyColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Widget? leading;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: z.card,
                borderRadius: BorderRadius.circular(ZRadius.x2l),
                border: Border.all(color: z.border),
              ),
              child: Icon(icon, size: 26, color: z.foreground),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: ZText.lg, fontWeight: FontWeight.w600, color: z.foreground)),
            const SizedBox(height: 8),
            if (leading != null) ...[leading!, const SizedBox(height: 8)],
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: ZText.sm, color: bodyColor ?? z.foregroundSubtle, height: 1.6)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      ),
    );
  }
}
