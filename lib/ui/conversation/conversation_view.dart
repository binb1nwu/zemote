import 'package:flutter/material.dart';

import '../../core/v4/conversation_store.dart';
import '../../core/v4/synced_topic.dart';
import '../../state/device_session.dart';
import '../../state/model_catalog.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'composer.dart';
import 'interaction_panel.dart';
import 'timeline.dart';

/// A task conversation: live timeline, blocking interactions, queue and
/// composer, all driven by one [ConversationStore].
class ConversationView extends StatefulWidget {
  const ConversationView({super.key, required this.device, required this.workspace, required this.sessionId});
  final DeviceSession device;
  final WorkspaceSession workspace;
  final String sessionId;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  late ConversationStore _store;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ConversationView old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId || old.workspace != widget.workspace) _bind();
  }

  void _bind() {
    _store = widget.workspace.conversation(widget.sessionId);
    // Not during build: markRead notifies the sidebar list.
    final tasks = widget.workspace.tasks;
    final id = widget.sessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) => tasks.markRead(id));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _send(String text) async {
    final s = S.of(context);
    final routing = _store.inputRouting;
    try {
      switch (routing['mode']) {
        case 'reject':
          showToast(context, '${routing['reasonCode'] ?? s.error}');
          return false;
        case 'choice':
          final disposition = await _heldQueueChoice();
          if (disposition == null) return false;
          await _store.sendText(text,
              heldQueueDisposition: disposition,
              expectedHeldQueueItemIds: [for (final q in _store.queueItems) '${q['queueItemId']}']);
        default:
          await _store.sendText(text);
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
      return true;
    } catch (e) {
      if (mounted) showToast(context, '$e');
      return false;
    }
  }

  Future<String?> _heldQueueChoice() {
    final s = S.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.heldQueueTitle),
        content: Text(s.heldQueueBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'clearQueueAndSend'), child: Text(s.clearQueueAndSend)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'keepQueueAndSend'), child: Text(s.keepQueueAndSend)),
        ],
      ),
    );
  }

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, widget.device]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final store = _store;
    if (!store.hasState) {
      return Center(
        child: store.status == TopicStatus.error
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(store.error ?? s.error, style: TextStyle(color: z.foregroundSubtle)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: store.refresh, child: Text(s.retry)),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const ZSpinner(size: 18),
                const SizedBox(height: 12),
                Text(s.loadingConversation, style: TextStyle(color: z.foregroundSubtle, fontSize: ZText.sm)),
              ]),
      );
    }
    final config = store.config;
    final catalog = widget.device.models;
    final provider = config['provider'] as String? ?? '';
    final model = config['model'] as String? ?? '';
    final option = catalog.find(provider, model);
    final providerName =
        catalog.providers.where((p) => p.providerId == provider).map((p) => p.name).firstOrNull;
    final modelLabel = option == null
        ? model
        : providerName == null
            ? option.displayName
            : '$providerName/${option.displayName}';
    final levels = [for (final l in (config['thoughtLevels'] as List? ?? const [])) '$l'];
    final pending = store.pendingInteractions
        .where((p) => (p['payload'] as Map?)?['kind'] != 'workspaceHookReview')
        .toList();
    final lastError = store.lastError;
    final queue = store.queueItems;
    final offline = !widget.device.status.isOnline;

    return Column(children: [
      if (offline || store.status == TopicStatus.recovering)
        _Banner(
          text: offline ? s.offlineBanner : s.syncing,
          color: z.warning,
        ),
      Expanded(
        child: Timeline(store: store, controller: _scroll),
      ),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (lastError != null && !store.running)
                _ErrorStrip(error: lastError),
              if (store.apiRetry != null)
                _Banner(
                  text: 'Retry ${store.apiRetry!['attempt']}/${store.apiRetry!['maxAttempts']} · ${store.apiRetry!['reasonCode']}',
                  color: z.warning,
                ),
              if (queue.isNotEmpty) _QueueStrip(store: store, queue: queue),
              if (store.backgroundWorks.any((w) => w['status'] == 'running'))
                _BackgroundStrip(store: store),
              if (pending.isNotEmpty) ...[
                InteractionPanel(store: store, interaction: pending.first),
                const SizedBox(height: 8),
              ],
              Composer(
                hint: store.running ? s.placeholderQueue : s.placeholderFollowUp,
                enabled: !offline,
                running: store.running,
                stopping: store.stopping,
                onStop: store.canStop ? () => _guard(store.stop) : null,
                onSend: _send,
                mode: config['mode'] as String? ?? 'build',
                onMode: (m) => _guard(() => store.switchMode(m)),
                modelLabel: modelLabel,
                catalog: catalog,
                onModel: (m) => _guard(() => store.switchModel(
                      m.providerId,
                      m.modelId,
                      _thoughtFor(m, config['thought'] as String?),
                    )),
                reasoningLevels: levels,
                reasoning: config['thought'] as String?,
                onReasoning: (l) => _guard(() => store.switchModel(provider, model, l)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  String _thoughtFor(ModelOption m, String? current) {
    if (m.reasoningLevels.isEmpty) return current ?? '';
    if (current != null && m.reasoningLevels.contains(current)) return current;
    return m.reasoningLevels.last;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZRadius.lg),
      ),
      child: Row(children: [
        StatusDot(color: color, pulse: true, size: 6),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: ZText.sm, color: context.z.foreground))),
      ]),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.error});
  final Map<String, dynamic> error;
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: z.destructive.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: z.destructive.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 16, color: z.destructive),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${error['message'] ?? error['code']}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: ZText.sm, color: z.foreground)),
        ),
      ]),
    );
  }
}

class _QueueStrip extends StatelessWidget {
  const _QueueStrip({required this.store, required this.queue});
  final ConversationStore store;
  final List<Map<String, dynamic>> queue;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final paused = store.queue['autoDrain'] == false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: z.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(paused ? s.queuePaused : '${s.queued} · ${queue.length}',
              style: TextStyle(fontSize: ZText.xs, color: z.foregroundSubtle)),
          const Spacer(),
          if (paused)
            TextButton(
              onPressed: () => store.setAutoDrain(true).catchError((_) {}),
              child: Text(s.resume, style: const TextStyle(fontSize: ZText.sm)),
            ),
        ]),
        for (final item in queue)
          Row(children: [
            Expanded(
              child: Text('${item['text']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: ZText.sm, color: z.foreground)),
            ),
            ZIconButton(
              icon: Icons.north_rounded,
              size: 28,
              iconSize: 15,
              tooltip: s.sendNow,
              onPressed: () => store.sendQueuedNow('${item['queueItemId']}').catchError((e) {
                if (context.mounted) showToast(context, '$e');
              }),
            ),
            ZIconButton(
              icon: Icons.close_rounded,
              size: 28,
              iconSize: 15,
              tooltip: s.delete,
              onPressed: () => store.deleteQueueItem('${item['queueItemId']}').catchError((e) {
                if (context.mounted) showToast(context, '$e');
              }),
            ),
          ]),
      ]),
    );
  }
}

class _BackgroundStrip extends StatelessWidget {
  const _BackgroundStrip({required this.store});
  final ConversationStore store;
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final running = store.backgroundWorks.where((w) => w['status'] == 'running').toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final w in running)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            decoration: BoxDecoration(
              color: z.surface,
              borderRadius: BorderRadius.circular(ZRadius.lg),
              border: Border.all(color: z.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const ZSpinner(size: 10),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text('${w['title']}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
              ),
              if (w['cancellable'] == true)
                ZIconButton(
                  icon: Icons.close_rounded,
                  size: 22,
                  iconSize: 13,
                  onPressed: () => store.cancelBackgroundWork('${w['workId']}').catchError((_) {}),
                ),
            ]),
          ),
      ]),
    );
  }
}
