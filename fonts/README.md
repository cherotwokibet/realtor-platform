# Bundled fonts

Every family a tenant can pick in `brand.fonts` must have a folder here before
`tenant validate` accepts it. `tenant prepare <id>` copies the tenant's display
and body families into `apps/realtor_app/assets/tenant/fonts/` and writes a
`fonts.json` manifest; the app registers them at start-up (no network, no
`google_fonts` package).

| Folder | Source (google/fonts, OFL 1.1) | Weights |
|--------|--------------------------------|---------|
| `Poppins/` | `ofl/poppins/Poppins-*.ttf` (static) | 400, 500, 600, 700 |
| `Inter/` | `ofl/inter/Inter[opsz,wght].ttf`, instanced at opsz 14 | 400, 500, 600, 700 |
| `Manrope/` | `ofl/manrope/Manrope[wght].ttf`, instanced | 400, 500, 600, 700 |

Files are named `<Family>-{Regular,Medium,SemiBold,Bold}.ttf`, static (no
variable axes, so `FontWeight` works on every platform) and subset to Latin,
Latin-1, Latin Extended-A, general punctuation and common symbols. English and
Swahili need nothing more, and it keeps each family under about 410 KB.

To add a family (fonttools 4.x):

```sh
fonttools varLib.instancer Family[wght].ttf wght=600 -o tmp.ttf --update-name-table
pyftsubset tmp.ttf --layout-features='*' --output-file=Family-SemiBold.ttf \
  --unicodes="U+0000-00FF,U+0100-017F,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122,U+2190-2193,U+2212,U+2215,U+FEFF,U+FFFD"
```

Copy the family's `OFL.txt` alongside. Folder names drop spaces
(`Plus Jakarta Sans` → `PlusJakartaSans/`).
