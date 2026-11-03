/**
 * Video normalisation (D6): one raw phone video in, an HLS ladder (360p and
 * 720p, 6 s segments) plus a poster frame out. ffmpeg is a child process; the
 * binary comes from FFMPEG_PATH (default `ffmpeg` on PATH). Pure of Firebase.
 */
import { spawn } from 'node:child_process';
import { mkdir, readdir } from 'node:fs/promises';
import { join } from 'node:path';

/** Longest clip we transcode, in seconds (a walkthrough, not a film). */
export const MAX_DURATION_SEC = 180;
/** Clips smaller than this on the long edge are rejected, like photos. */
export const MIN_LONG_EDGE = 720;
/** Rendition heights, tallest first; never upscaled past the source. */
export const LADDER = [720, 360] as const;
/** Bitrate ceiling per ladder height (kbit/s). */
export const MAX_KBPS: Record<(typeof LADDER)[number], number> = { 720: 2500, 360: 800 };

export class VideoRejectedError extends Error {}

export interface VideoInfo {
  width: number;
  height: number;
  durationSec: number;
  hasAudio: boolean;
}

/** Reads the facts we need from the stderr of `ffmpeg -i <file>`. */
export function parseProbe(stderr: string): VideoInfo {
  const dur = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/.exec(stderr);
  const vid = /Stream #\S+.*Video:.*?[,\s](\d{2,5})x(\d{2,5})[,\s\[]/.exec(stderr);
  if (!dur || !vid) throw new VideoRejectedError('not a readable video');
  return {
    width: Number(vid[1]),
    height: Number(vid[2]),
    durationSec: Number(dur[1]) * 3600 + Number(dur[2]) * 60 + Number(dur[3]),
    hasAudio: /Stream #\S+.*Audio:/.test(stderr),
  };
}

export function checkVideo(info: VideoInfo): void {
  if (info.durationSec > MAX_DURATION_SEC) {
    throw new VideoRejectedError(`video is ${Math.round(info.durationSec)} s; the limit is ${MAX_DURATION_SEC} s`);
  }
  if (Math.max(info.width, info.height) < MIN_LONG_EDGE) {
    throw new VideoRejectedError(`video is ${info.width}×${info.height}; the long edge must be at least ${MIN_LONG_EDGE}px`);
  }
}

/** ffmpeg arguments for the HLS ladder, written into `outDir`. */
export function hlsArgs(input: string, outDir: string, hasAudio: boolean): string[] {
  const split = LADDER.map((_, i) => `[s${i}]`).join('');
  const scales = LADDER.map((h, i) => `[s${i}]scale=-2:'min(${h},ih)'[v${i}]`).join(';');
  const maps = LADDER.flatMap((_, i) => ['-map', `[v${i}]`, ...(hasAudio ? ['-map', '0:a:0'] : [])]);
  const streams = LADDER.map((_, i) => (hasAudio ? `v:${i},a:${i}` : `v:${i}`)).join(' ');
  return [
    '-y', '-i', input,
    '-filter_complex', `[0:v]split=${LADDER.length}${split};${scales}`,
    ...maps,
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p', '-sc_threshold', '0', '-g', '48',
    // A ceiling per rung: kind to mobile data, and it gives each stream the
    // bandwidth the master playlist needs (without it, and without audio,
    // ffmpeg writes a master playlist that lists no streams).
    ...LADDER.flatMap((h, i) => [`-maxrate:v:${i}`, `${MAX_KBPS[h]}k`, `-bufsize:v:${i}`, `${MAX_KBPS[h] * 2}k`]),
    ...(hasAudio ? ['-c:a', 'aac', '-b:a', '96k'] : []),
    '-f', 'hls', '-hls_time', '6', '-hls_playlist_type', 'vod',
    '-hls_segment_filename', join(outDir, 'v%v_%03d.ts'),
    '-master_pl_name', 'master.m3u8',
    '-var_stream_map', streams,
    join(outDir, 'v%v.m3u8'),
  ];
}

/**
 * One progressive MP4 at the top rung (`video.mp4`): browsers that cannot
 * play HLS in a <video> tag (desktop Chrome, Firefox) play this instead.
 */
export function mp4Args(input: string, out: string, hasAudio: boolean): string[] {
  const h = LADDER[0];
  return [
    '-y', '-i', input,
    '-vf', `scale=-2:'min(${h},ih)'`,
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
    '-maxrate', `${MAX_KBPS[h]}k`, '-bufsize', `${MAX_KBPS[h] * 2}k`,
    ...(hasAudio ? ['-c:a', 'aac', '-b:a', '96k'] : ['-an']),
    '-movflags', '+faststart',
    out,
  ];
}

export function posterArgs(input: string, out: string): string[] {
  return ['-y', '-ss', '1', '-i', input, '-frames:v', '1', '-vf', "scale=-2:'min(720,ih)'", '-q:v', '4', out];
}

export function ffmpegBinary(): string {
  return process.env.FFMPEG_PATH || 'ffmpeg';
}

function run(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const p = spawn(ffmpegBinary(), args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    p.stderr.on('data', (d) => { err = (err + d).slice(-20_000); });
    p.on('error', reject);
    p.on('close', (code) => resolve(code === 0 ? err : `ffmpeg exited ${code}\n${err}`));
  });
}

export async function probeVideo(input: string): Promise<VideoInfo> {
  // `ffmpeg -i` with no output exits 1 after printing the stream facts.
  return parseProbe(await run(['-hide_banner', '-i', input]));
}

export interface ProcessedVideo {
  info: VideoInfo;
  /** Files written under outDir: master.m3u8, v0.m3u8, v1.m3u8, segments, video.mp4, poster.jpg. */
  files: string[];
}

export async function processVideo(input: string, outDir: string): Promise<ProcessedVideo> {
  const info = await probeVideo(input);
  checkVideo(info);
  await mkdir(outDir, { recursive: true });
  const log = await run(hlsArgs(input, outDir, info.hasAudio));
  if (log.startsWith('ffmpeg exited')) throw new VideoRejectedError('could not transcode this video');
  const mp4 = await run(mp4Args(input, join(outDir, 'video.mp4'), info.hasAudio));
  if (mp4.startsWith('ffmpeg exited')) throw new VideoRejectedError('could not transcode this video');
  const poster = await run(posterArgs(input, join(outDir, 'poster.jpg')));
  if (poster.startsWith('ffmpeg exited')) throw new VideoRejectedError('could not read a frame from this video');
  return { info, files: (await readdir(outDir)).sort() };
}

/**
 * Rewrites every URI in an HLS playlist (lines that are not tags, and
 * URI="..." attributes) with [url]. Firebase download links encode the whole
 * object path, so a player cannot resolve ffmpeg's relative names
 * (v0.m3u8, v0_001.ts) against them; absolute links play anywhere.
 */
export function absolutePlaylist(text: string, url: (name: string) => string): string {
  return text
    .split('\n')
    .map((line) => {
      const t = line.trim();
      if (!t) return line;
      if (t.startsWith('#')) return line.replace(/URI="([^"]+)"/g, (_m, u: string) => `URI="${/^https?:/.test(u) ? u : url(u)}"`);
      return /^https?:/.test(t) ? line : url(t);
    })
    .join('\n');
}
