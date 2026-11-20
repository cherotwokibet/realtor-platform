import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'listing_media.dart';
import 'providers.dart';

/// Ads (managers): the adverts the site shows on the home page's band and
/// among the results: running, scheduled, ended or paused at a glance, and
/// each one's words, photo, link, where it shows and when.
class AdsScreen extends ConsumerStatefulWidget {
  const AdsScreen({super.key});

  @override
  ConsumerState<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends ConsumerState<AdsScreen> {
  late Future<List<AdRow>> _ads = _load();

  Future<List<AdRow>> _load() => ref.read(adminRepositoryProvider).ads(ref.read(staffProvider)!);

  Future<void> _edit(AdRow? ad) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => AdEditorDialog(ad: ad));
    if (saved == true && mounted) {
      setState(() {
        _ads = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final media = ref.watch(listingMediaProvider);
    final today = DateTime.now();
    return FutureBuilder<List<AdRow>>(
      future: _ads,
      builder: (context, snap) {
        final ads = snap.data;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 12, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ads', style: t.headlineSmall),
              const SizedBox(height: 4),
              Text(
                ads == null ? 'Adverts on the site.' : 'Adverts on the site: ${ads.where((a) => a.runningOn(today)).length} running now.',
                style: t.bodyMedium?.copyWith(color: b.textMuted),
              ),
            ]),
            FilledButton.icon(key: const Key('add-ad'), onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('New ad')),
          ]),
          const SizedBox(height: 16),
          if (snap.hasError) Text("Couldn't load the ads: ${snap.error}", style: TextStyle(color: scheme.error)),
          if (ads == null && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (ads != null && ads.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text('No ads yet. The site shows its own banner until there is one.', style: t.bodyMedium?.copyWith(color: b.textMuted))),
            ),
          if (ads != null && ads.isNotEmpty)
            LayoutBuilder(builder: (context, box) {
              final across = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
              final w = (box.maxWidth - 16 * (across - 1)) / across;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final a in ads)
                  SizedBox(
                    width: w,
                    child: Material(
                      color: scheme.surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusMd + 4), side: BorderSide(color: scheme.outlineVariant)),
                      child: InkWell(
                        key: Key('ad-${a.id}'),
                        onTap: () => _edit(a),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          AspectRatio(
                            aspectRatio: 16 / 7,
                            child: switch (a.image == null ? null : media.url(a.image!)) {
                              final String u => Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: b.primarySoft)),
                              null => ColoredBox(color: b.primarySoft, child: Center(child: Icon(Icons.campaign_outlined, size: 40, color: scheme.primary))),
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                    child: Text(a.title,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                                _StateChip(state: a.stateOn(today)),
                              ]),
                              if (a.advertiser.isNotEmpty) Text(a.advertiser, style: t.bodySmall?.copyWith(color: b.textMuted)),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  switch (a.placement) { 'home' => 'Home page', 'results' => 'Among results', _ => 'Home page and results' },
                                  if (a.startsOn != null || a.endsOn != null) '${a.startsOn ?? 'now'} to ${a.endsOn ?? 'no end'}',
                                ].join(' · '),
                                style: t.bodySmall,
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
        ]);
      },
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (state) {
      'running' => (b.success.withValues(alpha: 0.12), b.success),
      'scheduled' => (b.primarySoft, scheme.primary),
      _ => (scheme.surfaceContainerHighest, b.textMuted),
    };
    return Container(
      key: Key('ad-state-$state'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(b.radiusSm)),
      child: Text(label(state), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

/// One advert: what it says, who it is for, its photo, where a tap goes,
/// where and when it shows; switched on or off.
class AdEditorDialog extends ConsumerStatefulWidget {
  const AdEditorDialog({super.key, this.ad});
  final AdRow? ad;

  @override
  ConsumerState<AdEditorDialog> createState() => _AdEditorDialogState();
}

class _AdEditorDialogState extends ConsumerState<AdEditorDialog> {
  late final AdRow _a = widget.ad ?? const AdRow();
  late final _title = TextEditingController(text: _a.title),
      _text = TextEditingController(text: _a.text),
      _advertiser = TextEditingController(text: _a.advertiser),
      _link = TextEditingController(text: _a.linkUrl ?? '');
  late String _placement = _a.placement;
  late bool _active = _a.active;
  late String? _starts = _a.startsOn, _ends = _a.endsOn, _image = _a.image, _id = _a.id;
  bool _busy = false, _tried = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _text, _advertiser, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  AdRow get _current => AdRow(
        id: _id,
        title: _title.text,
        text: _text.text,
        advertiser: _advertiser.text,
        linkUrl: _link.text.trim().isEmpty ? null : _link.text.trim(),
        image: _image,
        placement: _placement,
        active: _active,
        startsOn: _starts,
        endsOn: _ends,
      );

  /// Saves as it stands; the ad has an id after this.
  Future<bool> _store() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (_current.problems().isNotEmpty) return false;
    setState(() => _busy = true);
    try {
      _id = await ref.read(adminActionsProvider).saveAd(ref.read(staffProvider)!, _current);
      return true;
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final files = await ref.read(filePickerProvider).pick(accept: photoTypes.join(','));
    if (files.isEmpty || !mounted) return;
    // A new ad is saved first: its photo goes under its own id.
    if (_id == null && !await _store()) return;
    setState(() => _busy = true);
    try {
      _image = await ref.read(listingMediaProvider).uploadAdPhoto(ref.read(staffProvider)!, _id!, files.first);
      await _store();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not upload: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDay(bool start) async {
    final now = DateTime.now();
    final current = DateTime.tryParse((start ? _starts : _ends) ?? '');
    final d = await showDatePicker(context: context, initialDate: current ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
    if (d == null) return;
    final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => start ? _starts = s : _ends = s);
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${_a.title}"?'),
        content: const Text('It comes off the site at once. Pausing keeps it to run again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await ref.read(adminActionsProvider).deleteAd(ref.read(staffProvider)!, _id!);
      if (mounted) Navigator.pop(context, true);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final problems = _tried ? _current.problems() : const <String, String>{};
    final media = ref.watch(listingMediaProvider);
    Widget field(TextEditingController c, String labelText, String key, {String? hint, int lines = 1, Key? widgetKey}) => TextField(
          key: widgetKey,
          controller: c,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: labelText, hintText: hint, errorText: problems[key], border: const OutlineInputBorder()),
          onChanged: (_) => _tried ? setState(() {}) : null,
        );
    return AlertDialog(
      title: Text(_a.id == null ? 'New ad' : 'Edit ad'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            field(_title, 'Headline', 'title', hint: 'Riverside Gardens: now letting', widgetKey: const Key('ad-title-field')),
            const SizedBox(height: 12),
            field(_text, 'A line or two', 'text', lines: 2),
            const SizedBox(height: 12),
            field(_advertiser, 'Advertiser (optional)', 'advertiser'),
            const SizedBox(height: 12),
            field(_link, 'Link (optional)', 'linkUrl', hint: 'https://…   Empty: Enquire now opens your WhatsApp', widgetKey: const Key('ad-link-field')),
            const SizedBox(height: 16),
            Text('Photo', style: t.labelLarge),
            const SizedBox(height: 6),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(b.radiusSm),
                child: SizedBox(
                  width: 160,
                  height: 70,
                  child: switch (_image == null ? null : media.url(_image!)) {
                    final String u => Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: b.primarySoft)),
                    null => ColoredBox(color: b.primarySoft, child: Icon(_image == null ? Icons.image_outlined : Icons.check, color: scheme.primary)),
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _photo,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_image == null ? 'Add a photo' : 'Change photo'),
              ),
            ]),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Wide photos work best (about 16 by 7); under 20 MB.', style: t.bodySmall)),
            const SizedBox(height: 16),
            Text('Where it shows', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final (v, l) in const [('home', 'Home page'), ('results', 'Among results'), ('both', 'Both')])
                ChoiceChip(
                  key: Key('ad-placement-$v'),
                  label: Text(l),
                  selected: _placement == v,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _placement = v),
                ),
            ]),
            const SizedBox(height: 16),
            Text('When', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                  onPressed: () => _pickDay(true), icon: const Icon(Icons.event, size: 18), label: Text(_starts == null ? 'Starts now' : 'From $_starts')),
              if (_starts != null)
                IconButton(tooltip: 'No start day', onPressed: () => setState(() => _starts = null), icon: const Icon(Icons.close, size: 18)),
              OutlinedButton.icon(
                  onPressed: () => _pickDay(false), icon: const Icon(Icons.event_busy, size: 18), label: Text(_ends == null ? 'No end' : 'Until $_ends')),
              if (_ends != null) IconButton(tooltip: 'No end day', onPressed: () => setState(() => _ends = null), icon: const Icon(Icons.close, size: 18)),
            ]),
            if (problems['endsOn'] != null) Text(problems['endsOn']!, style: TextStyle(color: scheme.error)),
            SwitchListTile(
              key: const Key('ad-active'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Switched on'),
              subtitle: const Text('Off: kept here, but not shown on the site.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) Text("Couldn't save: $_error", style: TextStyle(color: scheme.error)),
          ]),
        ),
      ),
      actions: [
        if (_id != null) TextButton(onPressed: _busy ? null : _delete, child: Text('Delete', style: TextStyle(color: scheme.error))),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, _id != null && _id != _a.id), child: const Text('Cancel')),
        FilledButton(
          key: const Key('ad-save'),
          onPressed: _busy
              ? null
              : () async {
                  if (await _store() && context.mounted) Navigator.pop(context, true);
                },
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
