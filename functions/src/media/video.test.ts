import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { absolutePlaylist, checkVideo, ffmpegBinary, hlsArgs, MAX_DURATION_SEC, parseProbe, processVideo, VideoRejectedError } from './video';

const PROBE = `Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'a.mp4':
  Duration: 00:01:05.50, start: 0.000000, bitrate: 8000 kb/s
  Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(progressive), 1920x1080 [SAR 1:1 DAR 16:9], 7800 kb/s, 30 fps
  Stream #0:1[0x2](und): Audio: aac (LC), 48000 Hz, stereo, fltp, 128 kb/s`;

test('parseProbe reads size, duration and audio', () => {
  assert.deepEqual(parseProbe(PROBE), { width: 1920, height: 1080, durationSec: 65.5, hasAudio: true });
  assert.equal(parseProbe(PROBE.replace(/\n.*Audio.*/, '')).hasAudio, false);
});

test('parseProbe refuses text that is not a video', () => {
  assert.throws(() => parseProbe('a.mp4: Invalid data found when processing input'), VideoRejectedError);
});

test('checkVideo enforces the length and resolution limits', () => {
  const ok = { width: 1280, height: 720, durationSec: 30, hasAudio: true };
  checkVideo(ok);
  checkVideo({ ...ok, width: 720, height: 1280 }); // portrait
  assert.throws(() => checkVideo({ ...ok, durationSec: MAX_DURATION_SEC + 1 }), /limit is 180 s/);
  assert.throws(() => checkVideo({ ...ok, width: 640, height: 360 }), /at least 720px/);
});

test('hlsArgs maps audio only when the clip has some', () => {
  const withAudio = hlsArgs('in.mp4', 'out', true);
  assert.equal(withAudio[withAudio.indexOf('-var_stream_map') + 1], 'v:0,a:0 v:1,a:1');
  const silent = hlsArgs('in.mp4', 'out', false);
  assert.equal(silent[silent.indexOf('-var_stream_map') + 1], 'v:0 v:1');
  assert.ok(!silent.includes('aac'));
});

const hasFfmpeg = spawnSync(ffmpegBinary(), ['-version']).status === 0;

test('a 1080p clip becomes a 720p/360p HLS ladder and a poster', { skip: !hasFfmpeg && 'ffmpeg not installed' }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'video-'));
  const src = join(dir, 'in.mp4');
  const gen = spawnSync(ffmpegBinary(), [
    '-y', '-f', 'lavfi', '-i', 'testsrc=size=1920x1080:rate=24:duration=3',
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', src,
  ]);
  assert.equal(gen.status, 0, String(gen.stderr));
  const out = join(dir, 'hls');
  const r = await processVideo(src, out);
  assert.equal(r.info.height, 1080);
  for (const f of ['master.m3u8', 'v0.m3u8', 'v1.m3u8', 'video.mp4', 'poster.jpg']) assert.ok(r.files.includes(f), f);
  assert.ok(r.files.some((f) => f.endsWith('.ts')));
  const master = readFileSync(join(out, 'master.m3u8'), 'utf8');
  assert.match(master, /RESOLUTION=1280x720/);
  assert.match(master, /RESOLUTION=640x360/);
});

test('a silent clip still gets a master playlist that lists both rungs', { skip: !hasFfmpeg && 'ffmpeg not installed' }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'video-'));
  const src = join(dir, 'silent.mp4');
  spawnSync(ffmpegBinary(), ['-y', '-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=24:duration=2', '-pix_fmt', 'yuv420p', src]);
  const r = await processVideo(src, join(dir, 'hls'));
  assert.equal(r.info.hasAudio, false);
  const master = readFileSync(join(dir, 'hls', 'master.m3u8'), 'utf8');
  assert.equal(master.match(/#EXT-X-STREAM-INF/g)?.length, 2, master);
  assert.ok(r.files.includes('video.mp4'));
});

test('a clip below 720p is rejected before any transcoding', { skip: !hasFfmpeg && 'ffmpeg not installed' }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'video-'));
  const src = join(dir, 'small.mp4');
  spawnSync(ffmpegBinary(), ['-y', '-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=24:duration=1', '-pix_fmt', 'yuv420p', src]);
  await assert.rejects(processVideo(src, join(dir, 'hls')), /at least 720px/);
});

test('playlists get absolute links, so Firebase download URLs play (tags and existing URLs kept)', () => {
  const master = '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nv0.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=600000\nv1.m3u8\n';
  const url = (n: string) => `https://cdn/x%2F${n}?alt=media`;
  assert.equal(
    absolutePlaylist(master, url),
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nhttps://cdn/x%2Fv0.m3u8?alt=media\n#EXT-X-STREAM-INF:BANDWIDTH=600000\nhttps://cdn/x%2Fv1.m3u8?alt=media\n',
  );
  const media = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4.0,\nv0_000.ts\n#EXTINF:4.0,\nhttps://other/v0_001.ts\n#EXT-X-ENDLIST\n';
  assert.equal(
    absolutePlaylist(media, url),
    '#EXTM3U\n#EXT-X-MAP:URI="https://cdn/x%2Finit.mp4?alt=media"\n#EXTINF:4.0,\nhttps://cdn/x%2Fv0_000.ts?alt=media\n#EXTINF:4.0,\nhttps://other/v0_001.ts\n#EXT-X-ENDLIST\n',
  );
});
