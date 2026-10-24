import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';
import 'page_shell.dart';
import 'seo.dart';

const _languageNames = {'en': 'English', 'sw': 'Kiswahili'};

/// `/agent/<id>`: an active agent's profile, contacts and live homes.
class AgentPage extends StatelessComponent {
  const AgentPage({required this.tenant, required this.agent, required this.listings, super.key});
  final TenantConfig tenant;
  final ShareAgent agent;
  final List<ShareListing> listings;

  @override
  Component build(BuildContext context) {
    final canonical = 'https://${tenant.shareDomain}/agent/${agent.id}';
    final photo = agent.photo == null ? null : tenantMediaUrl(tenant, agent.photo!);
    final speaks = [for (final l in agent.languages) _languageNames[l] ?? l].join(' and ');
    final facts = [
      'EARB reg. ${agent.earbNo}',
      'Speaks $speaks',
      if (agent.responseMins != null) 'Usually replies within ${_duration(agent.responseMins!)}',
      if (agent.rating != null) 'Rated ${agent.rating!.toStringAsFixed(1)} of 5',
    ];
    final description =
        '${agent.name}, ${tenant.name} agent. ${listings.length} live ${listings.length == 1 ? 'home' : 'homes'}. Speaks $speaks.';
    final wa = Uri.https('wa.me', '/${agent.whatsapp.replaceAll('+', '')}', {
      'text': 'Hi ${agent.name}, I found you on ${tenant.name} ($canonical).',
    });

    return sharePage(
      tenant: tenant,
      title: '${agent.name} · ${tenant.name}',
      description: description,
      canonical: canonical,
      ogImage: photo ?? 'https://${tenant.appDomain}/og.png',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'RealEstateAgent',
        'name': agent.name,
        'url': canonical,
        if (photo != null) 'image': photo,
        'telephone': agent.phone,
        'knowsLanguage': agent.languages,
        'parentOrganization': {'@type': 'RealEstateAgent', 'name': tenant.name, 'url': 'https://${tenant.shareDomain}/'},
        'areaServed': {'@type': 'Country', 'name': 'Kenya'},
      },
      body: [
        div(classes: 'agent', [
          if (photo != null) img(src: photo, alt: agent.name, width: 72, height: 72),
          h1([Component.text(agent.name)]),
        ]),
        p(classes: 'facts', [Component.text(facts.join(' · '))]),
        div(classes: 'cta', [
          a(href: wa.toString(), classes: 'open', const [Component.text('Chat on WhatsApp')]),
          a(href: 'tel:${agent.phone}', classes: 'wa', const [Component.text('Call')]),
        ]),
        if (listings.isNotEmpty) ...[
          const h2([Component.text('Homes from this agent')]),
          listingCards(listings),
        ],
      ],
    );
  }

  static String _duration(int mins) => mins < 60 ? '$mins min' : '${(mins / 60).round()} h';
}
