# Realtime Estates: logo use

Source: `logo.ai` (sunset concept, vector; `reference/logo-sunset.png` is its 2000 px export) and `reference/original-roofline.png` (roofline concept, 2000 px). The roofline concept was traced to vector and recoloured to the app palette. The shapes and the Poppins wordmark are unchanged.

## Which logo where

| File | Use |
|---|---|
| `logo-sunset.svg` | **The main logo (client's choice, Nov 2026):** web header, app bar, admin, share pages, documents. Black roofs on a sunset, with the name and tagline |
| `logo-stacked-reverse.svg` | Roofline lockup on maroon: splash screens, social posts, signage |
| `logo-horizontal-reverse.svg` | Header on maroon, splash branding, WhatsApp share images |
| `mark.svg` / `mark-reverse.svg` | Symbol only: the app icon, and where the name already appears or space is tight |
| `favicon.svg` | Browser tabs and anywhere under 48 px. Roofs only |
| `logo-stacked.svg` / `logo-horizontal.svg` | The earlier roofline lockups on white, kept as the alternative |

The sunset logo is detailed, so give it room: at least 56 px high in a header. It has no version for dark backgrounds, so on maroon keep using the reverse roofline files.

The icons, splash screens, PWA images and share images are generated from these files: `node tools/tenant-cli/src/cli.ts icons realtime-estates`.

## Colours

| Role | Hex | Where |
|---|---|---|
| Maroon (primary) | `#5E0202` | Outer roofs, wordmark, app primary, icon background |
| Gold (accent) | `#D1992A` | Inner roofs, RTE monogram, badges |
| Gold for text | `#8A6418` | Tagline on white. Plain gold on white is only 2.5:1, so it fails for small text |
| White | `#FFFFFF` | Roofs and wordmark on maroon |

The original files used black where we now use maroon. This matches the app, which has always been maroon, and keeps gold as the shared thread between the two concepts.

## Rules

- **Clear space:** keep a margin around the logo equal to the height of the "RTE" letters.
- **Minimum size:** sunset logo 90 px wide, roofline stacked lockup 120 px wide, horizontal 140 px wide, mark 32 px wide. Below that, use the favicon.
- **Don't:** recolour outside the palette above, add shadows or outlines, stretch, rotate, set the wordmark in another font, or put the light version on photos (use the reverse version on a maroon band instead).
- **The legal name** "Realtime Estates Ltd" appears on the stacked lockup and in documents. The horizontal lockup drops "LTD" for space.

## Platform notes (Oct 2026)

- **Android adaptive icon:** 108 dp layers with the art inside the 66 dp safe zone. We use a monochrome layer for themed icons (Android 13+), and the foreground inset is 0 because the art is already padded.
- **iOS:** 1024 px opaque icon, plus dark (transparent background) and tinted (grayscale) variants for iOS 18+. A layered Liquid Glass `.icon` (Icon Composer) can be built later from `mark-reverse.svg`; that needs a Mac.
- **Google Play:** 512 px full-square PNG. Play rounds the corners itself.
- **PWA:** a maskable 512 px icon with the art inside the 40%-radius safe circle.
- **Android 12+ splash:** 1152 px art inside the 768 px circle on a maroon window, with the horizontal reverse lockup as branding.
