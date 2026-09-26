import 'package:flutter/material.dart';

import '../../state/device_session.dart';
import '../../state/model_catalog.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'composer.dart';

/// Empty state of a workspace: greeting + composer that creates a task
/// (`createSession` with `firstInput`), like ZCode's new-task screen.
class NewTaskView extends StatefulWidget {
  const NewTaskView({super.key, required this.device, required this.workspace, required this.onCreated});
  final DeviceSession device;
  final WorkspaceSession workspace;
  final ValueChanged<String> onCreated;

  @override
  State<NewTaskView> createState() => _NewTaskViewState();
}

class _NewTaskViewState extends State<NewTaskView> {
  String? _mode;
  ModelSelection? _model;

  ModelSelection? _effectiveModel(ModelCatalog catalog) {
    final picked = _model;
    if (picked != null && catalog.find(picked.providerId, picked.modelId) != null) return picked;
    return catalog.preferred;
  }

  Future<bool> _send(String text) async {
    try {
      final id = await widget.workspace.createTask(
        text,
        model: _effectiveModel(widget.device.models),
        mode: _mode,
      );
      widget.onCreated(id);
      return true;
    } catch (e) {
      if (mounted) showToast(context, '$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.device, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final z = context.z;
    final s = S.of(context);
    final catalog = widget.device.models;
    final model = _effectiveModel(catalog);
    final option = model == null ? null : catalog.find(model.providerId, model.modelId);
    final providerName = catalog.providers
        .where((p) => p.providerId == model?.providerId)
        .map((p) => p.name)
        .firstOrNull;
    final online = widget.device.status.isOnline;
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  s.greeting(DateTime.now().hour),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: z.foreground, height: 1.3),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: z.surface,
                    borderRadius: BorderRadius.circular(ZRadius.x2l),
                  ),
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(children: [
                        Icon(Icons.folder_outlined, size: 16, color: z.foregroundSubtle),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.workspace.workspace.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
                        ),
                      ]),
                    ),
                    Composer(
                      hint: s.placeholderNewTask,
                      enabled: online,
                      onSend: _send,
                      mode: _mode ?? 'build',
                      onMode: (m) => setState(() => _mode = m),
                      modelLabel: option == null
                          ? null
                          : providerName == null
                              ? option.displayName
                              : '$providerName/${option.displayName}',
                      catalog: catalog,
                      onModel: (m) => setState(() => _model = ModelSelection(
                            m.providerId,
                            m.modelId,
                            m.reasoningLevels.isEmpty
                                ? null
                                : (m.reasoningLevels.contains(model?.reasoningLevel)
                                    ? model?.reasoningLevel
                                    : m.reasoningLevels.last),
                          )),
                      reasoningLevels: option?.reasoningLevels ?? const [],
                      reasoning: model?.reasoningLevel,
                      onReasoning: model == null
                          ? null
                          : (l) => setState(() => _model = model.withReasoning(l)),
                    ),
                  ]),
                ),
                if (online && catalog.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(s.noModels,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: ZText.sm, color: z.foregroundSubtle)),
                  ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}
