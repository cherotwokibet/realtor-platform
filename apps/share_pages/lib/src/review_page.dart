import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'page_shell.dart';

/// Review links look like this (base64url, from submitReview's invites).
final reviewToken = RegExp(r'^[A-Za-z0-9_-]{20,40}$');

/// What the visitor sent, and what to say about it.
class ReviewFormState {
  const ReviewFormState({this.values = const {}, this.error, this.closed});
  final Map<String, String> values;

  /// A problem with the answers (no stars picked, too long).
  final String? error;

  /// The link can't take a review (used, expired, unknown): no form then.
  final String? closed;
}

/// `/review/<token>`: rate the agent after a viewing (P6-s03). A manager
/// reads each review before it shows; only a first name is kept.
class ReviewPage extends StatelessComponent {
  const ReviewPage({required this.tenant, required this.token, this.state = const ReviewFormState(), this.thanks = false, super.key});
  final TenantConfig tenant;
  final String token;
  final ReviewFormState state;
  final bool thanks;

  @override
  Component build(BuildContext context) {
    final f = state;
    return sharePage(
      tenant: tenant,
      title: 'How was your viewing? · ${tenant.name}',
      description: 'Rate your viewing with ${tenant.name}.',
      canonical: 'https://${tenant.shareDomain}/',
      ogImage: 'https://${tenant.appDomain}/og.png',
      jsonLd: const {},
      body: [
        h1([Component.text(thanks ? 'Thank you' : 'How was your viewing?')]),
        if (thanks)
          p([Component.text('Your review helps other people choose. ${tenant.name} reads every review before it is shown.')])
        else if (f.closed != null)
          p(classes: 'notice', [Component.text(f.closed!)])
        else
          form(action: '/review/$token', method: FormMethod.post, [
            if (f.error != null) p(classes: 'notice', [Component.text(f.error!)]),
            fieldset(classes: 'stars', [
              const legend([Component.text('Your rating of the agent')]),
              for (var n = 5; n >= 1; n--)
                label([
                  input(type: InputType.radio, name: 'rating', value: '$n', checked: f.values['rating'] == '$n'),
                  Component.text(' $n ${n == 1 ? 'star' : 'stars'}${n == 5 ? ' (excellent)' : n == 1 ? ' (poor)' : ''}'),
                ]),
            ]),
            const label(htmlFor: 'comment', [Component.text('What went well, or not? (optional)')]),
            textarea(name: 'comment', id: 'comment', rows: 4, attributes: const {'maxlength': '1000'}, [Component.text(f.values['comment'] ?? '')]),
            const label(htmlFor: 'name', [Component.text('Your first name (optional, shown with the review)')]),
            input(type: InputType.text, name: 'name', id: 'name', value: f.values['name'], attributes: const {'maxlength': '40', 'autocomplete': 'given-name'}),
            const button(type: ButtonType.submit, classes: 'open', [Component.text('Send review')]),
          ]),
      ],
    );
  }
}

/// The answers, checked before any call.
({int rating, String? comment, String? name})? parseReview(Map<String, String> form) {
  final rating = int.tryParse(form['rating'] ?? '');
  final comment = (form['comment'] ?? '').trim(), name = (form['name'] ?? '').trim();
  if (rating == null || rating < 1 || rating > 5 || comment.length > 1000 || name.length > 40) return null;
  return (rating: rating, comment: comment.isEmpty ? null : comment, name: name.isEmpty ? null : name);
}
