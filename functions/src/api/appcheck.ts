/**
 * App Check (D16) on the public callables: createLead, bookViewing,
 * logContactTap and submitReview. Rollout is watch first, enforce later, one switch per
 * Function: ENFORCE_APP_CHECK in functions/.env.<project> lists the ones to
 * enforce (comma-separated). Until then every call is served and logged as
 * verified or missing, so the logs show how many clients would be refused.
 *
 * The share pages call from their own server, where App Check cannot attest,
 * so they use HTTPS twins (shareCreateLead, ...) that only the `share-pages`
 * service account may invoke (Cloud Run IAM checks its OIDC token). The twins
 * speak the callable protocol and run the same code.
 */
import type { Request, Response } from 'express';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

export const PUBLIC_CALLABLES = ['createLead', 'bookViewing', 'logContactTap', 'submitReview'] as const;
export type PublicCallable = (typeof PUBLIC_CALLABLES)[number];

/** Which public callables enforce App Check, from ENFORCE_APP_CHECK. */
export function enforced(env: Record<string, string | undefined>): Set<PublicCallable> {
  const names = (env.ENFORCE_APP_CHECK ?? '').split(',').map((s) => s.trim());
  return new Set(PUBLIC_CALLABLES.filter((n) => names.includes(n) || names.includes('all')));
}

/** One log line per call: no personal data, just whether a token came. */
export function logAppCheck(fn: PublicCallable, verified: boolean): void {
  console.log(JSON.stringify({ appCheck: verified ? 'verified' : 'missing', fn }));
}

/** The twin of a public callable's name, e.g. createLead -> shareCreateLead. */
export const twinName = (fn: PublicCallable): string => `share${fn[0].toUpperCase()}${fn.slice(1)}`;

/** The share pages' service account, the only invoker of the twins. */
export const sharePagesInvoker = (project: string): string => `share-pages@${project}.iam.gserviceaccount.com`;

const body = z.object({ data: z.unknown() });

/**
 * An HTTPS handler that answers like a callable: POST {"data": ...} ->
 * 200 {"result": ...}, or the callable error JSON with its HTTP status.
 */
export function callableTwin(handler: (data: unknown) => Promise<unknown>): (req: Request, res: Response) => Promise<void> {
  return async (req, res) => {
    try {
      if (req.method !== 'POST') throw new HttpsError('invalid-argument', 'POST only');
      const parsed = body.safeParse(req.body);
      if (!parsed.success) throw new HttpsError('invalid-argument', 'expected {"data": ...}');
      res.status(200).json({ result: (await handler(parsed.data.data)) ?? null });
    } catch (e) {
      const err = e instanceof HttpsError ? e : new HttpsError('internal', 'internal');
      if (!(e instanceof HttpsError)) console.error(e);
      res.status(err.httpErrorCode.status).json({ error: err.toJSON() });
    }
  };
}
