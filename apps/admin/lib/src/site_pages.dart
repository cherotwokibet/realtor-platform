import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'providers.dart';

/// The site's own pages, by their slug, as staff and visitors call them.
const _pageNames = {
  'about': 'About us',
  'privacy': 'Privacy Policy',
  'terms': 'Terms and conditions',
  'faq': 'FAQs',
  'contact': 'Contact us',
};

const _pageIcons = {
  'about': Icons.info_outline,
  'privacy': Icons.privacy_tip_outlined,
  'terms': Icons.gavel_outlined,
  'faq': Icons.quiz_outlined,
  'contact': Icons.contact_support_outlined,
};

/// Content (P5-s07): the Privacy Policy, Terms and conditions, About us,
/// Contact us and FAQs the site shows at /privacy, /terms, ... once
/// published. Changes show within minutes, with no redeploy.
class ContentScreen extends ConsumerStatefulWidget {
  const ContentScreen({super.key});
  @override
  ConsumerState<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends ConsumerState<ContentScreen> {
  List<SitePageRow>? _pages;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pages = await ref.read(adminRepositoryProvider).sitePages(ref.read(staffProvider)!);
    if (mounted) setState(() => _pages = pages);
  }

  Future<void> _open(SitePageRow pg) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => PageEditorDialog(page: pg));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pages = _pages;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Content', style: t.headlineSmall),
      const SizedBox(height: 4),
      Text('The pages in the site\'s footer. Published changes show within minutes.', style: t.bodyMedium?.copyWith(color: b.textMuted)),
      const SizedBox(height: 16),
      if (pages == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        LayoutBuilder(builder: (context, box) {
          final across = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 600 ? 2 : 1);
          final w = (box.maxWidth - 16 * (across - 1)) / across;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final pg in pages)
              SizedBox(
                width: w,
                child: Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(b.radiusMd + 4),
                  child: InkWell(
                    key: Key('page-${pg.slug}'),
                    borderRadius: BorderRadius.circular(b.radiusMd + 4),
                    onTap: () => _open(pg),
                    child: Ink(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(b.radiusMd + 4), border: Border.all(color: scheme.outlineVariant)),
                      child: Row(children: [
                        DecoratedBox(
                          decoration: BoxDecoration(color: b.primarySoft, shape: BoxShape.circle),
                          child: Padding(padding: const EdgeInsets.all(10), child: Icon(_pageIcons[pg.slug] ?? Icons.article_outlined, color: scheme.primary)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_pageNames[pg.slug] ?? pg.slug, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              pg.title.isEmpty
                                  ? 'Not written yet'
                                  : '${pg.published ? 'Published' : 'Draft'} · /${pg.slug}${pg.updatedAt == null ? '' : ' · ${shortDateTime(pg.updatedAt!)}'}',
                              style: t.bodySmall?.copyWith(color: b.textMuted),
                            ),
                          ]),
                        ),
                        Icon(pg.published ? Icons.public : Icons.edit_note, color: pg.published ? b.success : b.textMuted),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
    ]);
  }
}

/// Kept for the Privacy page's shortcut: the same list in a dialog.
class SitePagesDialog extends StatelessWidget {
  const SitePagesDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Site pages'),
        content: const SizedBox(width: 760, height: 520, child: ContentScreen()),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}

/// One page: its title and text, written or previewed as the site shows it,
/// and whether it is published.
class PageEditorDialog extends ConsumerStatefulWidget {
  const PageEditorDialog({super.key, required this.page});
  final SitePageRow page;
  @override
  ConsumerState<PageEditorDialog> createState() => _PageEditorDialogState();
}

class _PageEditorDialogState extends ConsumerState<PageEditorDialog> {
  late final _title = TextEditingController(text: widget.page.title.isEmpty ? _pageNames[widget.page.slug] : widget.page.title);
  late final _body = TextEditingController(text: widget.page.body);
  late bool _published = widget.page.published;
  bool _busy = false, _preview = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminActionsProvider).savePage(
            ref.read(staffProvider)!,
            SitePageRow(slug: widget.page.slug, title: _title.text, body: _body.text, published: _published),
          );
      if (mounted) Navigator.pop(context, true);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(_pageNames[widget.page.slug] ?? widget.page.slug)),
        SegmentedButton<bool>(
          key: const Key('page-mode'),
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.edit_outlined), label: Text('Write')),
            ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined), label: Text('Preview')),
          ],
          selected: {_preview},
          onSelectionChanged: (s) => setState(() => _preview = s.first),
        ),
      ]),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            if (_preview) ...[
              Text(_title.text, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...pagePreview(context, _body.text),
            ] else ...[
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                key: const Key('page-body'),
                controller: _body,
                minLines: 12,
                maxLines: 28,
                maxLength: 20000,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  helperText: '"# " starts a heading, "- " a list item, an empty line a new paragraph. Preview shows it as the site will.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              subtitle: Text('Shown at /${widget.page.slug} and in the site footer.'),
              value: _published,
              onChanged: (v) => setState(() => _published = v),
            ),
            if (_error != null) Text("Couldn't save: $_error", style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

/// The page's text as the site lays it out: "# " headings, "- " list items,
/// paragraphs between empty lines.
List<Widget> pagePreview(BuildContext context, String body) {
  final t = Theme.of(context).textTheme;
  final out = <Widget>[];
  for (final block in body.split(RegExp(r'\n\s*\n'))) {
    final lines = block.trim().split('\n');
    if (lines.length == 1 && lines.first.isEmpty) continue;
    if (lines.every((l) => l.trimLeft().startsWith('- '))) {
      for (final l in lines) {
        out.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: t.bodyLarge),
            Expanded(child: Text(l.trimLeft().substring(2), style: t.bodyLarge)),
          ]),
        ));
      }
      out.add(const SizedBox(height: 8));
    } else if (lines.first.startsWith('#')) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(lines.first.replaceFirst(RegExp(r'^#+\s*'), ''), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ));
      if (lines.length > 1) out.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(lines.skip(1).join(' '), style: t.bodyLarge)));
    } else {
      out.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(lines.join(' '), style: t.bodyLarge?.copyWith(height: 1.5))));
    }
  }
  return out;
}
