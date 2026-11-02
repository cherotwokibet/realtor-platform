// Firebase settings for the Android and iOS apps (P4-s01). Nothing secret:
// these are the public identifiers every installed app carries. They are
// written as a generated asset (firebase.json beside tenant.json), never
// committed, and the app starts Firebase from it on phones; the web app
// reads Hosting's /__/firebase/init.json instead.

export interface AppListing {
  platform: 'ANDROID' | 'IOS' | 'WEB';
  appId: string;
  namespace?: string;
}

/** The Android and iOS apps registered for the tenant's package and bundle ids. */
export function pickApps(apps: AppListing[], androidId: string, iosId: string): { android?: string; ios?: string } {
  return {
    android: apps.find((a) => a.platform === 'ANDROID' && a.namespace === androidId)?.appId,
    ios: apps.find((a) => a.platform === 'IOS' && a.namespace === iosId)?.appId,
  };
}

export interface MobileFirebase {
  projectId: string;
  messagingSenderId: string;
  storageBucket?: string;
  android?: { appId: string; apiKey: string };
  ios?: { appId: string; apiKey: string; bundleId: string };
}

/** From google-services.json (`firebase apps:sdkconfig ANDROID`). */
export function fromGoogleServices(json: string, androidId: string): Pick<MobileFirebase, 'projectId' | 'messagingSenderId' | 'storageBucket' | 'android'> {
  const g = JSON.parse(json);
  const client = (g.client as any[]).find((c) => c.client_info?.android_client_info?.package_name === androidId);
  if (!client) throw new Error(`google-services.json has no client for ${androidId}`);
  return {
    projectId: g.project_info.project_id,
    messagingSenderId: String(g.project_info.project_number),
    storageBucket: g.project_info.storage_bucket || undefined,
    android: { appId: client.client_info.mobilesdk_app_id, apiKey: client.api_key[0].current_key },
  };
}

/** From GoogleService-Info.plist (`firebase apps:sdkconfig IOS`). */
export function fromServiceInfoPlist(plist: string): NonNullable<MobileFirebase['ios']> & { projectId: string; messagingSenderId: string } {
  const value = (key: string) => {
    const m = new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`).exec(plist);
    if (!m) throw new Error(`GoogleService-Info.plist has no ${key}`);
    return m[1];
  };
  return {
    appId: value('GOOGLE_APP_ID'),
    apiKey: value('API_KEY'),
    bundleId: value('BUNDLE_ID'),
    projectId: value('PROJECT_ID'),
    messagingSenderId: value('GCM_SENDER_ID'),
  };
}
