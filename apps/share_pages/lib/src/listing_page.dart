import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'lead_api.dart';
import 'listing.dart';
import 'page_shell.dart';
import 'seo.dart';

/// A form's state (enquiry or viewing): what was typed, what was wrong,
/// how it went.
class EnquiryFormState {
  const EnquiryFormState({this.values = const {}, this.errors = const {}, this.sent = false, this.failed = false, this.notice});
  final Map<String, String> values, errors;

  /// A message from the Functions to show above the form, e.g. a taken slot.
  final String? notice;

  /// The lead was stored (after the redirect back to the page).
  final bool sent;

  /// The Functions call failed; the visitor is pointed at WhatsApp instead.
  final bool failed;
}

class ListingPage extends StatelessComponent {
  const ListingPage({
    required this.tenant,
    required this.listing,
    this.agent,
    this.enquiry,
    this.viewing,
    this.viewingDays = const [],
    this.areaMedianRentKES,
    this.freeTimes,
    this.similar = const [],
    super.key,
  });
  final TenantConfig tenant;
  final ShareListing listing;

  /// The listing's agent when still active; links to their page.
  final ShareAgent? agent;

  /// Null when the server has no Functions to send leads to: no form, and
  /// the WhatsApp button links straight to wa.me without counting the tap.
  final EnquiryFormState? enquiry;

  /// The book-a-viewing form; null when there are no Functions to call.
  final EnquiryFormState? viewing;

  /// Days offered in the viewing form (see `viewingDays`).
  final List<({String value, String label})> viewingDays;

  /// The area's typical rent, for the "below typical rent" note on rentals.
  final int? areaMedianRentKES;

  /// After "Show free times" (`?day=`): that day and its free times only.
  final ({String day, List<String> times})? freeTimes;

  /// Up to three live homes like this one (`similarListings`, P7-s04).
  final List<ShareListing> similar;

  @override
  Component build(BuildContext context) {
    final seo = ListingSeo(tenant, listing);
    final l = listing;
    final facts = [
      if (l.beds > 0) '${l.beds} bed',
      if (l.baths > 0) '${l.baths} bath',
      [if (l.estate != null) l.estate!, ListingSeo.placeName(l.area)].join(', '),
    ].join(' · ');
    final wa = tenant.whatsappLink('Hi, I saw "${l.title}" (${seo.canonical}). Is it still available?');

    return sharePage(
      tenant: tenant,
      title: seo.title,
      description: seo.description,
      canonical: seo.canonical,
      ogImage: seo.ogImage,
      jsonLd: seo.jsonLd,
      body: [
        if (l.verified) const span(classes: 'badge', [Component.text('Verified')]),
        h1([Component.text(l.title)]),
        p(classes: 'price', priceText(l)),
        p(classes: 'facts', [Component.text(facts)]),
        if (l.purpose == Purpose.rent)
          if (percentBelowTypical(l.priceKES, areaMedianRentKES) case final int pct)
            p(classes: 'insight', [
              Component.text('$pct% below the typical rent in ${ListingSeo.placeName(l.area)} (${formatKes(areaMedianRentKES!)} a month)'),
            ]),
        if (l.photos.isNotEmpty)
          div(classes: 'photos', [
            for (final (i, ph) in l.photos.take(6).indexed)
              img(
                src: seo.mediaUrl(ph.card),
                alt: '${l.title}, photo ${i + 1}',
                width: 800,
                height: 600,
                attributes: {'loading': i == 0 ? 'eager' : 'lazy', 'decoding': 'async'},
              ),
          ]),
        p([Component.text(seo.description)]),
        if (l.amenities.isNotEmpty) ul([for (final am in l.amenities) li([Component.text(am)])]),
        div(classes: 'cta', [
          a(href: seo.appUrl, classes: 'open', const [Component.text('Open in app')]),
          if (wa != null)
            a(
              href: enquiry == null ? wa.toString() : '/go/whatsapp/${l.slug}',
              classes: 'wa',
              attributes: const {'rel': 'nofollow'},
              const [Component.text('Ask on WhatsApp')],
            ),
        ]),
        if (enquiry != null) _enquiryForm(enquiry!),
        if (viewing != null) _viewingForm(viewing!),
        if (agent != null) p([const Component.text('Listed by '), a(href: '/agent/${agent!.id}', [Component.text(agent!.name)])]),
        if (similar.isNotEmpty) section(classes: 'similar', [const h2([Component.text('Similar homes')]), listingCards(similar)]),
        p([a(href: '/area/${l.area}', [Component.text('More homes in ${ListingSeo.placeName(l.area)}')])]),
      ],
    );
  }

  Component _enquiryForm(EnquiryFormState f) {
    Component? error(String field) => f.errors[field] == null ? null : p(classes: 'error', [Component.text(f.errors[field]!)]);
    if (f.sent) {
      return section(id: 'enquire', [
        p(classes: 'notice', [Component.text('Thank you. ${tenant.name} will call or WhatsApp you about this home soon.')]),
      ]);
    }
    return section(id: 'enquire', classes: 'enquire', [
      const h2([Component.text('Ask about this home')]),
      if (f.notice != null) p(classes: 'notice', [Component.text(f.notice!)]),
      if (f.failed)
        const p(classes: 'notice', [Component.text('Sorry, we could not send that just now. Please try again or ask on WhatsApp.')]),
      form(action: '/listing/${listing.slug}/enquire#enquire', method: FormMethod.post, [
        const label(htmlFor: 'phone', [Component.text('Phone number')]),
        input(
          type: InputType.tel,
          name: 'phone',
          id: 'phone',
          value: f.values['phone'],
          attributes: const {'autocomplete': 'tel', 'inputmode': 'tel', 'placeholder': '0712 345 678', 'required': ''},
        ),
        ?error('phone'),
        const label(htmlFor: 'name', [Component.text('Your name (optional)')]),
        input(type: InputType.text, name: 'name', id: 'name', value: f.values['name'], attributes: const {'autocomplete': 'name', 'maxlength': '80'}),
        ?error('name'),
        const label(htmlFor: 'message', [Component.text('Message (optional)')]),
        textarea(name: 'message', id: 'message', rows: 3, attributes: const {'maxlength': '2000'}, [Component.text(f.values['message'] ?? '')]),
        ?error('message'),
        // Bots fill every field; people never see this one.
        const div(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
          label(htmlFor: 'website', [Component.text('Leave this empty')]),
          input(type: InputType.text, name: 'website', id: 'website', attributes: {'tabindex': '-1', 'autocomplete': 'off'}),
        ]),
        label(classes: 'consent', [
          input(type: InputType.checkbox, name: 'consent', value: 'yes', checked: f.values['consent'] == 'yes'),
          Component.text(
            'I agree that ${tenant.name} may contact me about this home and keep my details for up to $leadRetentionMonths months '
            '(Data Protection Act 2019).',
          ),
        ]),
        ?error('consent'),
        const button(type: ButtonType.submit, [Component.text('Send')]),
      ]),
    ]);
  }

  Component _viewingForm(EnquiryFormState f) {
    Component? error(String field) => f.errors[field] == null ? null : p(classes: 'error', [Component.text(f.errors[field]!)]);
    if (f.sent) {
      return section(id: 'viewing', [
        p(classes: 'notice', [Component.text('Viewing requested. ${tenant.name} will call or WhatsApp you to confirm the time.')]),
      ]);
    }
    Component select_(String name, String id, List<({String value, String label})> options) => select(
          name: name,
          id: id,
          [
            for (final o in options) option(value: o.value, selected: f.values[name] == o.value, [Component.text(o.label)]),
          ],
        );
    final free = freeTimes;
    return section(id: 'viewing', classes: 'enquire', [
      const h2([Component.text('Book a viewing')]),
      if (f.notice != null) p(classes: 'notice', [Component.text(f.notice!)]),
      if (f.failed)
        const p(classes: 'notice', [Component.text('Sorry, we could not book that just now. Please try again or ask on WhatsApp.')]),
      // Step 1 (optional, no script): pick a day to see only its free times.
      form(classes: 'days', action: '/listing/${listing.slug}#viewing', method: FormMethod.get, [
        const label(htmlFor: 'f-day', [Component.text('Day')]),
        select(name: 'day', id: 'f-day', [
          for (final d in viewingDays) option(value: d.value, selected: (free?.day ?? f.values['day']) == d.value, [Component.text(d.label)]),
        ]),
        const button(type: ButtonType.submit, classes: 'wa', [Component.text('Show free times')]),
      ]),
      form(action: '/listing/${listing.slug}/viewing#viewing', method: FormMethod.post, [
        if (free == null) ...[
          const label(htmlFor: 'v-day', [Component.text('Day')]),
          select_('day', 'v-day', viewingDays),
        ] else
          input(type: InputType.hidden, name: 'day', value: free.day),
        if (free != null && free.times.isEmpty)
          const p(classes: 'notice', [Component.text('No free times that day. Please pick another day above.')])
        else ...[
          label(htmlFor: 'v-time', [
            Component.text(free == null ? 'Time' : 'Free times on ${viewingDays.where((d) => d.value == free.day).firstOrNull?.label ?? free.day}'),
          ]),
          select_('time', 'v-time', [for (final t in free?.times ?? viewingTimes) (value: t, label: t)]),
        ],
        ?error('slot'),
        const label(htmlFor: 'v-name', [Component.text('Your name')]),
        input(
          type: InputType.text,
          name: 'name',
          id: 'v-name',
          value: f.values['name'],
          attributes: const {'autocomplete': 'name', 'maxlength': '80', 'required': ''},
        ),
        ?error('name'),
        const label(htmlFor: 'v-phone', [Component.text('Phone number')]),
        input(
          type: InputType.tel,
          name: 'phone',
          id: 'v-phone',
          value: f.values['phone'],
          attributes: const {'autocomplete': 'tel', 'inputmode': 'tel', 'placeholder': '0712 345 678', 'required': ''},
        ),
        ?error('phone'),
        const div(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
          label(htmlFor: 'v-website', [Component.text('Leave this empty')]),
          input(type: InputType.text, name: 'website', id: 'v-website', attributes: {'tabindex': '-1', 'autocomplete': 'off'}),
        ]),
        label(classes: 'consent', [
          input(type: InputType.checkbox, name: 'consent', value: 'yes', checked: f.values['consent'] == 'yes'),
          Component.text(
            'I agree that ${tenant.name} may contact me about this viewing and keep my details for up to $leadRetentionMonths months '
            '(Data Protection Act 2019).',
          ),
        ]),
        ?error('consent'),
        const button(type: ButtonType.submit, [Component.text('Request viewing')]),
      ]),
    ]);
  }
}
