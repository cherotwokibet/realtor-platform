// Per-tenant configs for flutter_launcher_icons and flutter_native_splash.
// Written into apps/realtor_app by `prepare` (gitignored): run
//   dart run flutter_launcher_icons && dart run flutter_native_splash:create
// after `flutter create`. `tenant flavors` writes one pair per tenant instead
// (flutter_launcher_icons-<flavor>.yaml, flutter_native_splash-<flavor>.yaml).

/** `androidOnly` for flavor configs: iOS flavors and web are not per-flavor yet. */
export function flutterConfigs(
  t: any,
  I = 'assets/tenant/icons',
  androidOnly = false,
): { launcherIcons: string; nativeSplash: string } {
  const primary: string = t.brand.colors.primary;
  const launcherIcons = `# Generated from tenants/${t.id}.json by tenant-cli. Do not edit.
flutter_launcher_icons:
  android: "ic_launcher"
  ios: ${!androidOnly}
  min_sdk_android: 21
  image_path: "${I}/app-icon-1024.png"
  remove_alpha_ios: true
  background_color_ios: "${primary}"
  image_path_ios_dark_transparent: "${I}/ios-dark-1024.png"
  image_path_ios_tinted_grayscale: "${I}/ios-tinted-1024.png"
  adaptive_icon_background: "${primary}"
  adaptive_icon_foreground: "${I}/android-foreground-432.png"
  adaptive_icon_foreground_inset: 0 # art already sits inside the 66 dp safe zone
  adaptive_icon_monochrome: "${I}/android-monochrome-432.png"
  web:
    generate: ${!androidOnly}
    image_path: "${I}/pwa-512.png"
    background_color: "${primary}"
    theme_color: "${primary}"
`;
  const nativeSplash = `# Generated from tenants/${t.id}.json by tenant-cli. Do not edit.
flutter_native_splash:
  color: "${primary}"
  image: "${I}/splash-1152.png"
  branding: "${I}/splash-branding-800x320.png"
  android_12:
    color: "${primary}"
    image: "${I}/splash-1152.png"
    branding: "${I}/splash-branding-800x320.png"
  web: ${!androidOnly}
  ios: ${!androidOnly}
  fullscreen: false
`;
  return { launcherIcons, nativeSplash };
}
