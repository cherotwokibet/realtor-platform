# Share pages (Phase 3)

Jaspr server-rendered pages on Cloud Run: `/listing/<slug>`, `/area/<slug>`, `/agent/<slug>` and home. They give Google indexable HTML and WhatsApp per-listing previews (OG image, JSON-LD `RealEstateListing`, sitemaps), then hand visitors to the Flutter app on `app.<domain>`.

Styles come from `tenant css <id>` (CSS variables), which match `packages/tokens`.
