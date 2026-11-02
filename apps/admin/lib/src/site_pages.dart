import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'providers.dart';

const _pageNames = {'about': 'About', 'privacy': 'Privacy notice', 'terms': 'Terms', 'faq': 'Questions (FAQ)', 'contact': 'Contact'};

/// Site pages (P5-s07): what the share site shows at /about, /privacy, ...
/// once published. Changes show within minutes, with no redeploy.
class SitePagesDialog extends ConsumerStatefulWidget {
  const SitePagesDialog({super.key});
  @override
  ConsumerState<SitePagesDialog> createState() => _SitePagesDialogState();
}

class _SitePagesDialogState extends ConsumerState<SitePagesDialog> {
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

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return AlertDialog(
      title: const Text('Site pages'),
      content: SizedBox(
        width: 520,
        child: pages == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                for (final pg in pages)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_pageNames[pg.slug] ?? pg.slug),
                    subtitle: Text(pg.title.isEmpty
                        ? 'Not written yet'
                        : '${pg.published ? 'Published' : 'Draft'} · /${pg.slug}${pg.updatedAt == null ? '' : ' · ${shortDateTime(pg.updatedAt!)}'}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final saved = await showDialog<bool>(context: context, builder: (_) => _PageEditor(page: pg));
                      if (saved == true) await _load();
                    },
                  ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _PageEditor extends ConsumerStatefulWidget {
  const _PageEditor({required this.page});
  final SitePageRow page;
  @override
  ConsumerState<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<_PageEditor> {
  late final _title = TextEditingController(text: widget.page.title.isEmpty ? _pageNames[widget.page.slug] : widget.page.title);
  late final _body = TextEditingController(text: widget.page.body);
  late bool _published = widget.page.published;
  bool _busy = false;
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
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_pageNames[widget.page.slug] ?? widget.page.slug),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 10,
                maxLines: 24,
                maxLength: 20000,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  helperText: '"# " starts a heading, "- " a list item, an empty line a new paragraph.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
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
