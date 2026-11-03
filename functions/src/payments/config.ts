import type { DarajaEnv, ShortcodeType } from './daraja';

/**
 * M-Pesa (P6-s01) is on for a project only when its functions/.env.<project-id>
 * (local, not committed) sets MPESA_ENV (sandbox or production), MPESA_SHORTCODE
 * and MPESA_TYPE (paybill or till), with MPESA_CONSUMER_KEY,
 * MPESA_CONSUMER_SECRET and MPESA_PASSKEY in Secret Manager. Until then the
 * payment functions are not deployed at all, so a deploy needs no secret.
 */
export interface MpesaConfig {
  env: DarajaEnv;
  shortcode: string;
  type: ShortcodeType;
}

export function mpesaConfig(env: Record<string, string | undefined>): MpesaConfig | null {
  const mode = env.MPESA_ENV?.trim();
  if (!mode) return null;
  if (mode !== 'sandbox' && mode !== 'production') throw new Error(`MPESA_ENV "${mode}" must be sandbox or production`);
  const shortcode = env.MPESA_SHORTCODE?.trim() ?? '';
  if (!/^\d{5,7}$/.test(shortcode)) throw new Error('MPESA_SHORTCODE must be the 5 to 7 digit paybill or till number');
  const type = env.MPESA_TYPE?.trim() || 'paybill';
  if (type !== 'paybill' && type !== 'till') throw new Error(`MPESA_TYPE "${type}" must be paybill or till`);
  return { env: mode, shortcode, type };
}

/** Where Safaricom posts results: the deployed payments-mpesaCallback function. */
export const callbackUrl = (project: string, region: string) => `https://${region}-${project}.cloudfunctions.net/payments-mpesaCallback`;
