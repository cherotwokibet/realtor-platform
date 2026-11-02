import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startTranscode } from './transcode';

function fakeFetch(status: number) {
  const calls: { url: string; init: RequestInit }[] = [];
  const f = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response('{}', { status });
  }) as unknown as typeof fetch;
  return { f, calls };
}

const opts = (f: typeof fetch) => ({ project: 'demo-realtor', region: 'europe-west1', token: async () => 'tok', fetch: f });

test('starts one job execution for the uploaded object', async () => {
  const { f, calls } = fakeFetch(200);
  const path = 'uploads/agents/agent-1/listings/listing-001/walk.mp4';
  assert.equal(await startTranscode(path, opts(f)), 'started');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://run.googleapis.com/v2/projects/demo-realtor/locations/europe-west1/jobs/transcode-video:run');
  assert.equal((calls[0].init.headers as Record<string, string>).authorization, 'Bearer tok');
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { overrides: { containerOverrides: [{ env: [{ name: 'OBJECT', value: path }] }] } });
});

test('no job deployed yet reads as no-job; other errors throw so the trigger retries', async () => {
  assert.equal(await startTranscode('x.mp4', opts(fakeFetch(404).f)), 'no-job');
  await assert.rejects(startTranscode('x.mp4', opts(fakeFetch(403).f)), /HTTP 403/);
});
