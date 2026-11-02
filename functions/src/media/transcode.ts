/**
 * Video transcoding (D15) runs in the Cloud Run job `transcode-video`, whose
 * image has Debian's ffmpeg (functions/transcode.Dockerfile) and runs
 * handleListingVideo. The Storage trigger only starts an execution for the
 * uploaded object, so Functions never need an ffmpeg binary.
 */
export const TRANSCODE_JOB = 'transcode-video';

export interface StartOptions {
  project: string;
  region: string;
  /** OAuth access token of the Function's service account. */
  token: () => Promise<string>;
  fetch?: typeof fetch;
}

/** 'no-job' until the job image is deployed (Terraform `transcode_image`). */
export async function startTranscode(object: string, opts: StartOptions): Promise<'started' | 'no-job'> {
  const url = `https://run.googleapis.com/v2/projects/${opts.project}/locations/${opts.region}/jobs/${TRANSCODE_JOB}:run`;
  const res = await (opts.fetch ?? fetch)(url, {
    method: 'POST',
    headers: { authorization: `Bearer ${await opts.token()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ overrides: { containerOverrides: [{ env: [{ name: 'OBJECT', value: object }] }] } }),
  });
  if (res.status === 404) return 'no-job';
  if (!res.ok) throw new Error(`starting ${TRANSCODE_JOB} failed: HTTP ${res.status}`);
  return 'started';
}
