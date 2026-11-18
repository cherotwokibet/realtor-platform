import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';

/// The areas that match what has been typed, best first: names that start
/// with it, then names with a word that starts with it, then any that
/// contain it. At most [max].
List<MapEntry<String, String>> areaSuggestions(Map<String, String> names, String typed, {int max = 8}) {
  final q = typed.trim().toLowerCase();
  if (q.isEmpty) return const [];
  int rank(String name) {
    final n = name.toLowerCase();
    if (n.startsWith(q)) return 0;
    if (n.split(RegExp(r'[\s\-]+')).any((w) => w.startsWith(q))) return 1;
    return 2;
  }

  final hits = names.entries.where((e) => e.value.toLowerCase().contains(q)).toList()
    ..sort((a, b) {
      final r = rank(a.value).compareTo(rank(b.value));
      return r != 0 ? r : a.value.compareTo(b.value);
    });
  return hits.take(max).toList();
}

/// A location box that suggests areas while typing, as on the big portals:
/// a list under the box with the typed part of each name in bold and
/// underlined. Picking one puts its name in the box and calls [onPicked]
/// with its slug. [field] draws the box itself with the given controller
/// and focus node.
class AreaSuggestField extends ConsumerStatefulWidget {
  const AreaSuggestField({super.key, required this.controller, required this.field, this.onPicked});
  final TextEditingController controller;
  final Widget Function(BuildContext context, TextEditingController controller, FocusNode focus) field;
  final ValueChanged<String>? onPicked;

  @override
  ConsumerState<AreaSuggestField> createState() => _AreaSuggestFieldState();
}

class _AreaSuggestFieldState extends ConsumerState<AreaSuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(areaNamesProvider).value ?? const <String, String>{};
    return LayoutBuilder(
      builder: (context, box) => RawAutocomplete<MapEntry<String, String>>(
        textEditingController: widget.controller,
        focusNode: _focus,
        displayStringForOption: (e) => e.value,
        optionsBuilder: (value) {
          final hits = areaSuggestions(names, value.text);
          // Nothing to suggest once the box holds exactly one area's name.
          if (hits.length == 1 && hits.single.value.toLowerCase() == value.text.trim().toLowerCase()) return const [];
          return hits;
        },
        onSelected: (e) => widget.onPicked?.call(e.key),
        fieldViewBuilder: (context, controller, focus, _) => widget.field(context, controller, focus),
        optionsViewBuilder: (context, onSelected, options) => _Suggestions(
          width: box.maxWidth,
          typed: widget.controller.text,
          options: options.toList(),
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.width, required this.typed, required this.options, required this.onSelected});
  final double width;
  final String typed;
  final List<MapEntry<String, String>> options;
  final ValueChanged<MapEntry<String, String>> onSelected;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final at = AutocompleteHighlightedOption.of(context);
    final q = typed.trim().toLowerCase();
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          key: const Key('area-suggestions'),
          elevation: 6,
          color: scheme.surface,
          borderRadius: BorderRadius.circular(b.radiusSm),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: 320),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, i) {
                final o = options[i];
                final name = o.value;
                final from = name.toLowerCase().indexOf(q);
                final strong = TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline, color: scheme.onSurface);
                return Material(
                  color: i == at ? b.surfaceAlt : Colors.transparent,
                  child: InkWell(
                    key: Key('area-suggestion-${o.key}'),
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: b.spacing.md, vertical: b.spacing.sm + 2),
                      child: Row(children: [
                        Icon(Icons.place_outlined, size: 18, color: b.textMuted),
                        SizedBox(width: b.spacing.sm),
                        Expanded(
                          child: Text.rich(
                            from < 0 || q.isEmpty
                                ? TextSpan(text: name)
                                : TextSpan(children: [
                                    TextSpan(text: name.substring(0, from)),
                                    TextSpan(text: name.substring(from, from + q.length), style: strong),
                                    TextSpan(text: name.substring(from + q.length)),
                                  ]),
                            style: text.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
