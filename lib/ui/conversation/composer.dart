import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/model_catalog.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

const composerModes = ['build', 'edit', 'plan', 'yolo'];

IconData modeIcon(String mode) => switch (mode) {
      'build' => Icons.pan_tool_alt_outlined,
      'edit' => Icons.edit_outlined,
      'plan' => Icons.checklist_rounded,
      'yolo' => Icons.bolt_rounded,
      _ => Icons.tune_rounded,
    };

/// Main chat input shell (`rounded-2xl`, the approved exception in DESIGN.md)
/// with ZCode's toolbar: mode · model · reasoning · send/stop.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.hint,
    required this.onSend,
    this.enabled = true,
    this.running = false,
    this.stopping = false,
    this.onStop,
    this.mode,
    this.onMode,
    this.modelLabel,
    this.catalog,
    this.onModel,
    this.reasoningLevels = const [],
    this.reasoning,
    this.onReasoning,
    this.autofocus = false,
  });

  final String hint;

  /// Returns true when the text was accepted (the field is then cleared).
  final Future<bool> Function(String text) onSend;
  final bool enabled;
  final bool running;
  final bool stopping;
  final VoidCallback? onStop;
  final String? mode;
  final ValueChanged<String>? onMode;
  final String? modelLabel;
  final ModelCatalog? catalog;
  final ValueChanged<ModelOption>? onModel;
  final List<String> reasoningLevels;
  final String? reasoning;
  final ValueChanged<String>? onReasoning;
  final bool autofocus;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending || !widget.enabled) return;
    setState(() => _sending = true);
    try {
      if (await widget.onSend(text)) _text.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _pickMode() {
    final s = S.of(context);
    showZSheet<void>(context, title: s.modeLabel(widget.mode ?? 'build'), builder: (ctx) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        for (final m in composerModes)
          ZMenuItem(
            icon: modeIcon(m),
            title: s.modeLabel(m),
            subtitle: s.modeDescription(m),
            selected: m == widget.mode,
            onTap: () {
              Navigator.pop(ctx);
              widget.onMode?.call(m);
            },
          ),
      ]);
    });
  }

  void _pickModel() {
    final catalog = widget.catalog;
    if (catalog == null) return;
    final s = S.of(context);
    showZSheet<void>(context, title: s.model, builder: (ctx) {
      if (catalog.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Text(s.noModels, style: TextStyle(color: ctx.z.foregroundSubtle)),
        );
      }
      return ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        for (final p in catalog.providers) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(p.name,
                style: TextStyle(fontSize: ZText.xs, color: ctx.z.foregroundSubtlest)),
          ),
          for (final m in p.models)
            ZMenuItem(
              title: m.displayName,
              selected: widget.modelLabel == '${p.name}/${m.displayName}' ||
                  widget.modelLabel == m.modelId,
              onTap: () {
                Navigator.pop(ctx);
                widget.onModel?.call(m);
              },
            ),
        ],
      ]);
    });
  }

  void _pickReasoning() {
    final s = S.of(context);
    showZSheet<void>(context, title: s.reasoning, builder: (ctx) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        for (final l in widget.reasoningLevels)
          ZMenuItem(
            title: s.reasoningLevel(l),
            selected: l == widget.reasoning,
            onTap: () {
              Navigator.pop(ctx);
              widget.onReasoning?.call(l);
            },
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final hasText = _text.text.trim().isNotEmpty;
    final showStop = widget.running && !hasText && widget.onStop != null;
    return Container(
      decoration: BoxDecoration(
        color: z.card,
        borderRadius: BorderRadius.circular(ZRadius.x2l),
        border: Border.all(color: z.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
          },
          child: TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            style: TextStyle(fontSize: 16, height: 1.45, color: z.foreground),
            decoration: InputDecoration(
              hintText: widget.hint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 8, 8),
          child: Row(children: [
            if (widget.onMode != null)
              ZChipButton(
                icon: modeIcon(widget.mode ?? 'build'),
                label: s.modeLabel(widget.mode ?? 'build'),
                onPressed: widget.enabled ? _pickMode : null,
                maxWidth: 150,
              ),
            Expanded(
              child: widget.onModel == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: ZChipButton(
                        label: widget.modelLabel ?? s.model,
                        onPressed: widget.enabled ? _pickModel : null,
                        maxWidth: 220,
                      ),
                    ),
            ),
            if (widget.onReasoning != null && widget.reasoningLevels.isNotEmpty)
              ZChipButton(
                icon: Icons.psychology_outlined,
                label: s.reasoningLevel(widget.reasoning ?? widget.reasoningLevels.first),
                onPressed: widget.enabled ? _pickReasoning : null,
                maxWidth: 90,
              ),
            const SizedBox(width: 4),
            if (showStop)
              ZIconButton(
                icon: widget.stopping ? Icons.hourglass_top_rounded : Icons.stop_rounded,
                filled: true,
                tooltip: s.stop,
                onPressed: widget.stopping ? null : widget.onStop,
              )
            else
              ZIconButton(
                icon: Icons.arrow_upward_rounded,
                filled: true,
                tooltip: s.send,
                onPressed: hasText && widget.enabled && !_sending ? _send : null,
              ),
          ]),
        ),
      ]),
    );
  }
}
