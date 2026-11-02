import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'providers.dart';

/// Managers' off-plan projects (P5-s06): what `/projects` and each
/// `/project/<slug>` share page show once published. Only offered when the
/// tenant has the `offPlan` switch on.
class ProjectsDialog extends ConsumerStatefulWidget {
  const ProjectsDialog({super.key});
  @override
  ConsumerState<ProjectsDialog> createState() => _ProjectsDialogState();
}

class _ProjectsDialogState extends ConsumerState<ProjectsDialog> {
  List<OffPlanProject>? _projects;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(adminRepositoryProvider).projects(ref.read(staffProvider)!);
    if (mounted) setState(() => _projects = list);
  }

  Future<void> _edit(OffPlanProject? p) async {
    final saved = await showDialog<String>(context: context, builder: (_) => ProjectEditorDialog(project: p));
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return AlertDialog(
      title: const Text('Off-plan projects'),
      content: SizedBox(
        width: 560,
        child: projects == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : projects.isEmpty
                ? const Text('No projects yet. Add one to show it on the website at /projects.')
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final p in projects)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          subtitle: Text([
                            p.published ? 'Published' : 'Draft',
                            'from ${formatKes(p.fromKES)}',
                            'ready ${p.completion}',
                            if (p.updatedAt != null) shortDateTime(p.updatedAt!),
                          ].join(' · ')),
                          trailing: IconButton(tooltip: 'Edit ${p.name}', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(p)),
                        ),
                    ]),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add_business_outlined), label: const Text('Add project')),
      ],
    );
  }
}

class _UnitRow {
  _UnitRow(OffPlanUnit u)
      : type = u.type,
        beds = TextEditingController(text: '${u.beds}'),
        size = TextEditingController(text: u.sizeSqm == null ? '' : '${u.sizeSqm}'),
        from = TextEditingController(text: u.fromKES == 0 ? '' : '${u.fromKES}'),
        available = TextEditingController(text: '${u.available}');
  String type;
  final TextEditingController beds, size, from, available;

  OffPlanUnit get value => OffPlanUnit(
        type: type,
        beds: int.tryParse(beds.text.trim()) ?? -1,
        sizeSqm: size.text.trim().isEmpty ? null : int.tryParse(size.text.trim()) ?? 0,
        fromKES: int.tryParse(from.text.replaceAll(RegExp(r'[,\s]'), '')) ?? 0,
        available: int.tryParse(available.text.trim()) ?? -1,
      );

  void dispose() {
    for (final c in [beds, size, from, available]) {
      c.dispose();
    }
  }
}

class _StageRow {
  _StageRow(OffPlanStage s)
      : stage = TextEditingController(text: s.stage),
        percent = TextEditingController(text: s.percent == 0 ? '' : '${s.percent}');
  final TextEditingController stage, percent;
  OffPlanStage get value => (stage: stage.text, percent: int.tryParse(percent.text.trim()) ?? 0);
  void dispose() {
    stage.dispose();
    percent.dispose();
  }
}

/// One project: units with from-prices, the payment plan and handover.
class ProjectEditorDialog extends ConsumerStatefulWidget {
  const ProjectEditorDialog({super.key, this.project});
  final OffPlanProject? project;
  @override
  ConsumerState<ProjectEditorDialog> createState() => _ProjectEditorDialogState();
}

class _ProjectEditorDialogState extends ConsumerState<ProjectEditorDialog> {
  late final OffPlanProject _p = widget.project ??
      const OffPlanProject(paymentPlan: [(stage: 'Deposit on booking', percent: 10), (stage: 'On handover', percent: 90)]);
  late final _name = TextEditingController(text: _p.name),
      _developer = TextEditingController(text: _p.developer),
      _summary = TextEditingController(text: _p.summary),
      _completion = TextEditingController(text: _p.completion);
  late String _area = _p.area;
  late bool _published = _p.published;
  late final _units = [for (final u in _p.units) _UnitRow(u)];
  late final _stages = [for (final s in _p.paymentPlan) _StageRow(s)];
  List<AreaOption> _areas = const [];
  bool _tried = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(adminRepositoryProvider).areas().then((a) {
      if (mounted) setState(() => _areas = a);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _developer, _summary, _completion]) {
      c.dispose();
    }
    for (final u in _units) {
      u.dispose();
    }
    for (final s in _stages) {
      s.dispose();
    }
    super.dispose();
  }

  OffPlanProject get _current => OffPlanProject(
        slug: _p.slug,
        name: _name.text,
        developer: _developer.text,
        area: _area,
        summary: _summary.text,
        completion: _completion.text,
        units: [for (final u in _units) u.value],
        paymentPlan: [for (final s in _stages) s.value],
        published: _published,
      );

  Future<void> _save() async {
    final p = _current;
    setState(() {
      _tried = true;
      _error = null;
    });
    if (p.problems().isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final slug = await ref.read(adminActionsProvider).saveProject(ref.read(staffProvider)!, p);
      if (mounted) Navigator.pop(context, slug);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed() => _tried ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    final problems = _tried ? current.problems() : const <String, String>{};
    InputDecoration deco(String label, {String? key, String? hint}) =>
        InputDecoration(labelText: label, hintText: hint, errorText: key == null ? null : problems[key], border: const OutlineInputBorder(), isDense: true);
    Widget field(TextEditingController c, String label, {String? key, String? hint, int lines = 1, TextInputType? keyboard}) => TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines * 2,
          keyboardType: keyboard,
          decoration: deco(label, key: key, hint: hint),
          onChanged: (_) => _changed(),
        );
    final areaKnown = _areas.any((a) => a.slug == _area);

    return AlertDialog(
      title: Text(_p.slug == null ? 'Add project' : 'Edit ${_p.name}'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            field(_name, 'Project name', key: 'name', hint: 'Acacia Heights'),
            const SizedBox(height: 12),
            field(_developer, 'Developer', key: 'developer'),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: areaKnown ? _area : null,
                  isExpanded: true,
                  decoration: deco('Area', key: 'area'),
                  items: [for (final a in _areas) DropdownMenuItem(value: a.slug, child: Text(a.name))],
                  onChanged: (v) => setState(() => _area = v ?? ''),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: field(_completion, 'Handover month', key: 'completion', hint: 'YYYY-MM')),
            ]),
            const SizedBox(height: 12),
            field(_summary, 'About the project', key: 'summary', lines: 4),
            const SizedBox(height: 16),
            Text('Units', style: theme.textTheme.titleSmall),
            if (problems['units'] != null) Text(problems['units']!, style: TextStyle(color: theme.colorScheme.error)),
            for (final (i, u) in _units.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: u.type,
                      isExpanded: true,
                      decoration: deco('Type'),
                      items: [for (final t in offPlanUnitTypes) DropdownMenuItem(value: t, child: Text(label(t)))],
                      onChanged: (v) => setState(() => u.type = v ?? u.type),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: field(u.beds, 'Beds', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: field(u.size, 'm²', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: field(u.from, 'From KES', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: field(u.available, 'Left', keyboard: TextInputType.number)),
                  IconButton(
                    tooltip: 'Remove unit ${i + 1}',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _units.length == 1 ? null : () => setState(() => _units.removeAt(i).dispose()),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _units.length >= 20 ? null : () => setState(() => _units.add(_UnitRow(const OffPlanUnit()))),
                icon: const Icon(Icons.add),
                label: const Text('Add unit type'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Payment plan · ${current.planTotal}% of 100%', style: theme.textTheme.titleSmall),
            if (problems['paymentPlan'] != null) Text(problems['paymentPlan']!, style: TextStyle(color: theme.colorScheme.error)),
            for (final (i, s) in _stages.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(flex: 5, child: field(s.stage, 'Stage ${i + 1}', hint: 'On signing the sale agreement')),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: field(s.percent, '%', keyboard: TextInputType.number)),
                  IconButton(
                    tooltip: 'Remove stage ${i + 1}',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _stages.length == 1 ? null : () => setState(() => _stages.removeAt(i).dispose()),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _stages.length >= 12 ? null : () => setState(() => _stages.add(_StageRow((stage: '', percent: 0)))),
                icon: const Icon(Icons.add),
                label: const Text('Add stage'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              subtitle: const Text('Shown on the website at /projects.'),
              value: _published,
              onChanged: (v) => setState(() => _published = v),
            ),
            if (_error != null) Text("Couldn't save: $_error", style: TextStyle(color: theme.colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
