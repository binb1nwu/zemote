import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/v4/conversation_store.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import 'turn_model.dart';

/// Right-aligned user message (`bg-card`, `rounded-xl`).
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.row, required this.store});
  final Map<String, dynamic> row;
  final ConversationStore store;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final origin = row['origin'] as String? ?? 'realUser';
    var text = row['text'] as String? ?? '';
    final epilogue = (row['epilogueStart'] as num?)?.toInt();
    if (epilogue != null && epilogue <= text.length) text = text.substring(0, epilogue).trimRight();
    final attachments = (row['attachments'] as List?) ?? const [];
    if (origin != 'realUser' && origin != 'workflowLaunch') {
      // Background results, goal continuations… are system inputs: render
      // them as a quiet line instead of a user bubble.
      final label = switch (origin) {
        'backgroundResult' => s.background,
        'goalContinuation' => 'Goal',
        _ => origin,
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('↳ $label',
            style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtlest)),
      );
    }
    final actions = row['actions'] as Map? ?? const {};
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.86,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () => _menu(context, text, actions['canEdit'] == true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: z.card,
                borderRadius: BorderRadius.circular(ZRadius.xl),
                border: Border.all(color: z.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text,
                    style: TextStyle(fontSize: ZText.base, height: 1.55, color: z.foreground)),
                if (attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final a in attachments.whereType<Map>())
                        _Chip(icon: Icons.attach_file, label: '${a['fileName'] ?? ''}'),
                    ]),
                  ),
                if (row['guided'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('guide',
                        style: TextStyle(fontSize: ZText.xs, color: z.foregroundSubtlest)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _menu(BuildContext context, String text, bool canEdit) {
    final s = S.of(context);
    showZSheet<void>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        ZMenuItem(
          icon: Icons.copy_rounded,
          title: s.copy,
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: text));
            showToast(context, s.copied);
          },
        ),
        if (canEdit)
          ZMenuItem(
            icon: Icons.edit_outlined,
            title: s.edit,
            onTap: () async {
              Navigator.pop(ctx);
              final edited = await _editDialog(context, text);
              if (edited == null || edited.trim().isEmpty) return;
              try {
                await store.editUserQuery(row, edited.trim());
              } catch (e) {
                if (context.mounted) showToast(context, '$e');
              }
            },
          ),
      ]);
    });
  }

  Future<String?> _editDialog(BuildContext context, String text) {
    final controller = TextEditingController(text: text);
    final s = S.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.edit),
        content: TextField(controller: controller, maxLines: 8, minLines: 2, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(s.send)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(ZRadius.md),
        border: Border.all(color: z.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: z.foregroundSubtle),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
        ),
      ]),
    );
  }
}

/// Assistant answer: full-width Markdown plus copy / retry / feedback.
class AssistantText extends StatelessWidget {
  const AssistantText({super.key, required this.row, required this.store, this.showActions = true});
  final Map<String, dynamic> row;
  final ConversationStore store;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final text = row['text'] as String? ?? '';
    final streaming = row['state'] == 'streaming';
    final actions = row['actions'] as Map? ?? const {};
    final feedback = row['feedback'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (text.isEmpty && streaming)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ZSpinner(size: 12, color: z.foregroundSubtlest),
        )
      else
        MarkdownView(text),
      if (row['state'] == 'failed' || row['state'] == 'interrupted')
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(row['state'] == 'failed' ? S.of(context).toolFailed : S.of(context).statusInterrupted,
              style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtlest)),
        ),
      if (showActions && !streaming && text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            ZIconButton(
              icon: Icons.copy_rounded,
              iconSize: 15,
              size: 28,
              tooltip: S.of(context).copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                showToast(context, S.of(context).copied);
              },
            ),
            if (actions['canRetry'] == true)
              ZIconButton(
                icon: Icons.refresh_rounded,
                iconSize: 16,
                size: 28,
                tooltip: S.of(context).retryTurn,
                onPressed: () => _run(context, () => store.retryTurn(row)),
              ),
            ZIconButton(
              icon: feedback == 'like' ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              iconSize: 15,
              size: 28,
              onPressed: () =>
                  _run(context, () => store.setFeedback(row, feedback == 'like' ? null : 'like')),
            ),
            ZIconButton(
              icon: feedback == 'dislike' ? Icons.thumb_down_alt : Icons.thumb_down_alt_outlined,
              iconSize: 15,
              size: 28,
              onPressed: () => _run(
                  context, () => store.setFeedback(row, feedback == 'dislike' ? null : 'dislike')),
            ),
          ]),
        ),
    ]);
  }
}

Future<void> _run(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
  } catch (e) {
    if (context.mounted) showToast(context, '$e');
  }
}

/// Collapsible reasoning line ("Thinking" / "Thought · 3s").
class ReasoningRow extends StatefulWidget {
  const ReasoningRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  State<ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<ReasoningRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final row = widget.row;
    final streaming = row['state'] == 'streaming';
    final ms = (row['durationMs'] as num?)?.toInt();
    final label = streaming ? s.thinking : (ms != null ? '${s.thought} · ${formatDuration(ms)}' : s.thought);
    final text = (row['text'] as String? ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(ZRadius.md),
        onTap: text.isEmpty ? null : () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (streaming) ...[const ZSpinner(size: 11), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
            if (text.isNotEmpty)
              Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 14, color: z.foregroundSubtlest),
          ]),
        ),
      ),
      if (_open || (streaming && text.isNotEmpty))
        Container(
          margin: const EdgeInsets.only(top: 2, bottom: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: z.border, width: 2))),
          child: Text(
            streaming && !_open && text.length > 280 ? '…${text.substring(text.length - 280)}' : text,
            style: TextStyle(fontSize: ZText.sm, height: 1.55, color: z.foregroundSubtle),
          ),
        ),
    ]);
  }
}

IconData toolIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('bash') || n.contains('shell') || n.contains('exec')) return Icons.terminal_rounded;
  if (n == 'read' || n.contains('read')) return Icons.description_outlined;
  if (n.contains('edit') || n.contains('write') || n.contains('patch')) return Icons.edit_note_rounded;
  if (n.contains('grep') || n.contains('glob') || n.contains('search') || n == 'ls') {
    return Icons.search_rounded;
  }
  if (n.contains('web') || n.contains('fetch')) return Icons.public_rounded;
  if (n.contains('todo')) return Icons.checklist_rounded;
  if (n.contains('agent') || n == 'task') return Icons.smart_toy_outlined;
  if (n.contains('question') || n.contains('plan')) return Icons.help_outline_rounded;
  if (n.startsWith('mcp')) return Icons.extension_outlined;
  return Icons.build_outlined;
}

/// Compact tool call line; tap to expand input / output / diff.
class ToolCallRow extends StatefulWidget {
  const ToolCallRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final row = widget.row;
    final name = row['toolName'] as String? ?? 'tool';
    final status = row['status'] as String? ?? 'running';
    final summary = toolSummary(row);
    final Widget statusWidget = switch (status) {
      'inputStreaming' || 'running' => const ZSpinner(size: 11),
      'pendingApproval' => Text(s.toolPending,
          style: TextStyle(fontSize: ZText.xs, color: z.confirmForeground)),
      'error' => Icon(Icons.close_rounded, size: 14, color: z.destructive),
      'cancelled' => Icon(Icons.block_rounded, size: 13, color: z.foregroundSubtlest),
      _ => const SizedBox.shrink(),
    };
    final diff = _diffDisplay(row);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(ZRadius.md),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(toolIcon(name), size: 15, color: z.foregroundSubtle),
            const SizedBox(width: 8),
            Text(name,
                style: TextStyle(
                    fontSize: ZText.sm, fontWeight: FontWeight.w500, color: z.foreground)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ZText.sm,
                    color: z.foregroundSubtle,
                    fontFamily: zMonoFamily,
                    fontFamilyFallback: zMonoFallback,
                  )),
            ),
            if (diff != null) ...[
              Text('+${diff['additions'] ?? 0}',
                  style: TextStyle(fontSize: ZText.xs, color: z.success)),
              const SizedBox(width: 4),
              Text('-${diff['deletions'] ?? 0}',
                  style: TextStyle(fontSize: ZText.xs, color: z.destructive)),
              const SizedBox(width: 6),
            ],
            statusWidget,
          ]),
        ),
      ),
      if (_open) _details(context, row, diff),
    ]);
  }

  static Map<String, dynamic>? _diffDisplay(Map<String, dynamic> row) {
    final display = row['display'];
    if (display is Map<String, dynamic>) {
      if (display['kind'] == 'file_diff') return display;
      final result = display['result'];
      if (result is Map<String, dynamic> && result['kind'] == 'file_diff') return result;
    }
    return null;
  }

  Widget _details(BuildContext context, Map<String, dynamic> row, Map<String, dynamic>? diff) {
    final z = context.z;
    final s = S.of(context);
    final input = row['input'];
    String inputText;
    if (input is Map && input['command'] is String) {
      inputText = input['command'] as String;
    } else if (input != null) {
      inputText = const JsonEncoder.withIndent('  ').convert(input);
    } else {
      inputText = row['inputText'] as String? ?? '';
    }
    final output = row['output'];
    var outputText = output is Map ? (output['text'] as String? ?? '') : '';
    final preview = row['outputPreview'];
    if (outputText.isEmpty && preview is Map) outputText = '${preview['text'] ?? ''}';
    final error = row['error'] as Map?;
    return Padding(
      padding: const EdgeInsets.only(left: 23, bottom: 6, top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (inputText.trim().isNotEmpty) ...[
          _label(context, s.input),
          CodeBlock(code: inputText, maxHeight: 220),
        ],
        if (diff != null) ...[
          const SizedBox(height: 6),
          DiffView(display: diff),
        ],
        if (outputText.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _label(context, s.output),
          CodeBlock(
              code: outputText.length > 20000 ? '${outputText.substring(0, 20000)}\n…' : outputText,
              maxHeight: 280),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${error['message'] ?? error['code']}',
                style: TextStyle(fontSize: ZText.sm, color: z.destructive)),
          ),
      ]),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: TextStyle(fontSize: ZText.xs, color: context.z.foregroundSubtlest)),
      );
}

/// Unified diff of a `file_diff` tool display.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.display});
  final Map<String, dynamic> display;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final hunks = (display['structuredPatch'] as List? ?? const []).whereType<Map>();
    final lines = <Widget>[];
    for (final hunk in hunks) {
      lines.add(_line(context, '@@ -${hunk['oldStart']},${hunk['oldLines']} +${hunk['newStart']},${hunk['newLines']} @@',
          z.foregroundSubtlest, null));
      for (final l in (hunk['lines'] as List? ?? const [])) {
        final text = '$l';
        if (text.startsWith('+')) {
          lines.add(_line(context, text, z.foreground, z.success.withValues(alpha: 0.14)));
        } else if (text.startsWith('-')) {
          lines.add(_line(context, text, z.foreground, z.destructive.withValues(alpha: 0.14)));
        } else {
          lines.add(_line(context, text, z.foregroundSubtle, null));
        }
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: z.codeBackground,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: z.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Text('${display['filePath'] ?? ''}',
              style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _line(BuildContext context, String text, Color color, Color? bg) => Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: Text(text,
            style: TextStyle(
              fontFamily: zMonoFamily,
              fontFamilyFallback: zMonoFallback,
              fontSize: 12,
              height: 1.45,
              color: color,
            )),
      );
}

class SubagentRow extends StatelessWidget {
  const SubagentRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final running = row['status'] == 'running';
    final summary = (row['summaryText'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.smart_toy_outlined, size: 15, color: z.foregroundSubtle),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['subagentType'] ?? 'agent'}',
                style: TextStyle(fontSize: ZText.sm, fontWeight: FontWeight.w500, color: z.foreground)),
            if (summary.isNotEmpty)
              Text(summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
          ]),
        ),
        if (running) const ZSpinner(size: 11),
        if (row['status'] == 'failed') Icon(Icons.close_rounded, size: 14, color: z.destructive),
      ]),
    );
  }
}

/// Timeline markers (compact, model change, retries…).
class MarkerRow extends StatelessWidget {
  const MarkerRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final m = row['marker'] as Map? ?? const {};
    final text = switch (m['type']) {
      'compact' => '${s.compact} · ${m['status']}',
      'modelChange' => m['fromModel'] != null
          ? '${m['fromModel']} → ${m['toModel']}'
          : '${m['toModel']}',
      'goalSet' => 'Goal: ${m['objective']}',
      'goalVerify' => 'Goal #${m['iteration']} · ${m['outcome']}',
      'retryNotice' => 'Retry #${m['attempt']} · ${m['reasonCode']}',
      'checkpointRestored' => 'Checkpoint restored',
      'forkNotice' || 'forkCreated' => 'Fork',
      _ => '${m['type']}',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Divider(color: z.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text, style: TextStyle(fontSize: ZText.xs, color: z.foregroundSubtlest)),
        ),
        Expanded(child: Divider(color: z.border, height: 1)),
      ]),
    );
  }
}

Widget workRowWidget(Map<String, dynamic> row, ConversationStore store) {
  final key = ValueKey('r${row['rowId']}');
  return switch (row['kind']) {
    'reasoning' => ReasoningRow(key: key, row: row),
    'toolCall' => ToolCallRow(key: key, row: row),
    'subagent' => SubagentRow(key: key, row: row),
    'timelineMarker' => MarkerRow(key: key, row: row),
    'assistantText' => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AssistantText(row: row, store: store, showActions: false),
      ),
    'artifact' => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _Chip(icon: Icons.insert_drive_file_outlined, label: '${row['displayName']}'),
      ),
    'hookInvocation' => Builder(
        key: key,
        builder: (context) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('hook · ${row['hookEventName']} · ${row['state']}',
              style: TextStyle(fontSize: ZText.xs, color: context.z.foregroundSubtlest)),
        ),
      ),
    _ => SizedBox.shrink(key: key),
  };
}
