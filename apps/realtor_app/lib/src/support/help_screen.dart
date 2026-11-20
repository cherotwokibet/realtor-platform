import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../nav.dart';
import '../providers.dart';
import 'site_services.dart';

/// `/help`: Help & feedback. A question, a problem, feedback or a complaint
/// goes to the realtor's support inbox (the admin's Support page); a phone or
/// an email lets them reply. Kept as long as an enquiry, as the privacy
/// notice says.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key, this.from});

  /// The page they came from, so staff see what it is about.
  final String? from;

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _kind = 'question';
  final _message = TextEditingController(), _name = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  bool _busy = false, _sent = false, _tried = false;
  String? _error;

  static const kinds = [
    ('question', 'A question', Icons.help_outline),
    ('problem', 'A problem', Icons.bug_report_outlined),
    ('feedback', 'Feedback', Icons.chat_bubble_outline),
    ('complaint', 'A complaint', Icons.report_outlined)
  ];

  @override
  void dispose() {
    for (final c in [_message, _name, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _phoneValue => _phone.text.trim().isEmpty ? null : normaliseKenyanPhone(_phone.text);
  bool get _emailOk => _email.text.trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Map<String, String> get _problems => {
        if (_message.text.trim().length < 5) 'message': 'Write a little more (at least 5 characters).',
        if (_phone.text.trim().isNotEmpty && _phoneValue == null) 'phone': 'A Kenyan mobile, e.g. 0712 345 678.',
        if (!_emailOk) 'email': 'That email does not look right.',
      };

  Future<void> _send() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (_problems.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(siteServicesProvider).sendFeedback(
            kind: _kind,
            message: _message.text,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            phone: _phoneValue,
            email: _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase(),
            page: widget.from,
          );
      if (mounted) setState(() => _sent = true);
    } on FeedbackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    final problems = _tried ? _problems : const <String, String>{};
    InputDecoration deco(String label, String key, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint, errorText: problems[key], border: const OutlineInputBorder());

    return Scaffold(
      backgroundColor: b.surfaceAlt,
      appBar: AppBar(leading: const AppBack(), centerTitle: true, title: const Text('Help & feedback')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
            if (_sent)
              Padding(
                key: const Key('help-sent'),
                padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
                child: Column(children: [
                  Icon(Icons.mark_email_read_outlined, size: 48, color: scheme.primary),
                  SizedBox(height: b.spacing.md),
                  Text('Thank you. ${tenant.name} has your message.',
                      textAlign: TextAlign.center, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(height: b.spacing.sm),
                  Text(
                    _phoneValue != null || _email.text.trim().isNotEmpty
                        ? 'They will reply to you as soon as they can.'
                        : 'You left no phone or email, so they cannot reply, but they will read it.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: b.textMuted),
                  ),
                ]),
              )
            else ...[
              Text('How can we help?', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: b.spacing.xs),
              Text('Ask a question, tell us about a problem, or share what you think.', style: text.bodyMedium?.copyWith(color: b.textMuted)),
              SizedBox(height: b.spacing.lg),
              Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
                for (final (k, label, icon) in kinds)
                  ChoiceChip(
                    key: Key('help-kind-$k'),
                    avatar: Icon(icon, size: 18),
                    label: Text(label),
                    selected: _kind == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ]),
              SizedBox(height: b.spacing.lg),
              TextField(
                key: const Key('help-message'),
                controller: _message,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: deco('Your message', 'message').copyWith(alignLabelWithHint: true),
                onChanged: (_) => _tried ? setState(() {}) : null,
              ),
              SizedBox(height: b.spacing.sm),
              TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: deco('Your name (optional)', 'name')),
              SizedBox(height: b.spacing.md),
              Text('So we can reply (optional)', style: text.labelLarge),
              SizedBox(height: b.spacing.sm),
              TextField(
                key: const Key('help-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: deco('Phone', 'phone', hint: '0712 345 678'),
                onChanged: (_) => _tried ? setState(() {}) : null,
              ),
              SizedBox(height: b.spacing.sm),
              TextField(
                key: const Key('help-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: deco('Email', 'email'),
                onChanged: (_) => _tried ? setState(() {}) : null,
              ),
              SizedBox(height: b.spacing.md),
              Text('${tenant.name} keeps your message and details to answer it, as its privacy notice says.',
                  style: text.bodySmall?.copyWith(color: b.textMuted)),
              if (_error != null) Padding(padding: EdgeInsets.only(top: b.spacing.sm), child: Text(_error!, style: TextStyle(color: scheme.error))),
              SizedBox(height: b.spacing.lg),
              FilledButton.icon(
                key: const Key('help-send'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(_busy ? 'Sending…' : 'Send'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
