import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';

/// How long a lead's details are kept (D12); quoted on the consent tick.
const _retentionMonths = 24;

Future<void> showEnquirySheet(BuildContext context, {required ListingSummary listing}) =>
    _show(context, (_) => _LeadSheet(listing: listing, viewing: false));

Future<void> showViewingSheet(BuildContext context, {required ListingSummary listing}) =>
    _show(context, (_) => _LeadSheet(listing: listing, viewing: true));

Future<void> _show(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: builder(ctx)),
    );

/// One form for both actions: an enquiry (phone, optional name and message)
/// or a viewing request (day, time, name, phone). Both need the consent tick.
class _LeadSheet extends ConsumerStatefulWidget {
  const _LeadSheet({required this.listing, required this.viewing});
  final ListingSummary listing;
  final bool viewing;

  @override
  ConsumerState<_LeadSheet> createState() => _LeadSheetState();
}

class _LeadSheetState extends ConsumerState<_LeadSheet> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _message = TextEditingController();
  late final _days = viewingDays(ref.read(clockProvider)());
  late String _day = _days.first.value;
  String _time = '10:00';
  bool _consent = false;
  bool _sending = false;
  Map<String, String> _errors = const {};
  String? _notice;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = normaliseKenyanPhone(_phone.text);
    final name = _name.text.trim();
    final errors = {
      if (phone == null) 'phone': 'Enter a Kenyan mobile number, like 0712 345 678.',
      if (widget.viewing && name.isEmpty) 'name': 'Enter your name so the agent knows who to expect.',
      if (!_consent) 'consent': 'Tick the box so we may contact you.',
    };
    setState(() {
      _errors = errors;
      _notice = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _sending = true);
    final leads = ref.read(leadRepositoryProvider);
    final tenant = ref.read(tenantProvider);
    try {
      if (widget.viewing) {
        await leads.bookViewing(listingId: widget.listing.id, slot: viewingSlot(_day, _time), name: name, phone: phone!);
      } else {
        final message = _message.text.trim();
        await leads.enquire(listingId: widget.listing.id, phone: phone!, name: name.isEmpty ? null : name, message: message.isEmpty ? null : message);
      }
    } on LeadException catch (e) {
      setState(() {
        _sending = false;
        _notice = switch (e.code) {
          'already-exists' => 'That time is taken. Please pick another.',
          'invalid-argument' when e.message.startsWith('slot: ') => 'Please pick another time: ${e.message.substring(6)}.',
          _ => 'Sorry, we could not send that just now. Please try again or use WhatsApp.',
        };
      });
      return;
    }
    if (!mounted) return;
    final done = widget.viewing
        ? 'Viewing requested. ${tenant.name} will call or WhatsApp you to confirm the time.'
        : 'Thank you. ${tenant.name} will call or WhatsApp you about this home soon.';
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    String? err(String k) => _errors[k];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(b.spacing.gutter, 0, b.spacing.gutter, b.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.viewing ? 'Book a viewing' : 'Ask about this home', style: text.titleLarge),
          SizedBox(height: b.spacing.xs),
          Text(widget.listing.title, style: text.bodyMedium?.copyWith(color: b.textMuted)),
          if (_notice != null) ...[
            SizedBox(height: b.spacing.md),
            Text(_notice!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
          if (widget.viewing) ...[
            SizedBox(height: b.spacing.md),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('day'),
                  isExpanded: true,
                  initialValue: _day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [for (final d in _days) DropdownMenuItem(value: d.value, child: Text(d.label))],
                  onChanged: (v) => setState(() => _day = v!),
                ),
              ),
              SizedBox(width: b.spacing.md),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('time'),
                  isExpanded: true,
                  initialValue: _time,
                  decoration: const InputDecoration(labelText: 'Time'),
                  items: [for (final t in viewingTimes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _time = v!),
                ),
              ),
            ]),
          ],
          SizedBox(height: b.spacing.md),
          TextField(
            key: const Key('name'),
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(labelText: widget.viewing ? 'Your name' : 'Your name (optional)', errorText: err('name')),
          ),
          TextField(
            key: const Key('phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(labelText: 'Phone number', hintText: '0712 345 678', errorText: err('phone')),
          ),
          if (!widget.viewing) ...[
            SizedBox(height: b.spacing.md),
            TextField(
              key: const Key('message'),
              controller: _message,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message (optional)'),
            ),
          ],
          CheckboxListTile(
            key: const Key('consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(
              'I agree that ${tenant.name} may contact me about this ${widget.viewing ? 'viewing' : 'home'} and keep my details '
              'for up to $_retentionMonths months (Data Protection Act 2019).',
              style: text.bodySmall,
            ),
            subtitle: err('consent') == null
                ? null
                : Text(err('consent')!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
          ),
          SizedBox(height: b.spacing.md),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending…' : (widget.viewing ? 'Request viewing' : 'Send')),
          ),
        ],
      ),
    );
  }
}
