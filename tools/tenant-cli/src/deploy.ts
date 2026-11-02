/**
 * `tenant deploy <id> <env>` (P1-s05): one command for what infra/terraform/README.md
 * lists by hand: Functions, the two container images, Terraform, and the
 * Hosting sites. This file only plans; cli.ts runs the steps.
 *
 * The plan check exists because a hand-typed deploy once planned with empty
 * variables: Terraform proposed unlinking the project's billing account and
 * pointing Cloud Run at "/share-pages:<tag>". Deploy refuses such a plan.
 */

export const ENVS = ['dev', 'stage', 'prod'] as const;
export type Env = (typeof ENVS)[number];

export const PARTS = ['functions', 'images', 'infra', 'web'] as const;
export type Part = (typeof PARTS)[number];

export interface DeployInputs {
  id: string;
  env: Env;
  project: string;
  region: string;
  /** Image tag: the short commit the images are built from. */
  tag: string;
  /** XXXXXX-XXXXXX-XXXXXX; only infra needs it. */
  billing?: string;
  parts: readonly Part[];
}

export interface Step {
  part: Part;
  title: string;
  argv: string[];
  /** Repo-relative working directory. */
  cwd: string;
  env?: Record<string, string>;
  /** Skip when this repo-relative path exists (one-time setup steps). */
  skipIfExists?: string;
  /** Not a command: check the saved Terraform plan, then ask before applying. */
  checkPlan?: boolean;
}

/** Cloud Shell's IPv6 route times out on uploads to Firebase; IPv4 first avoids it. */
const NODE_IPV4 = { NODE_OPTIONS: '--dns-result-order=ipv4first' };
const TF_DIR = 'infra/terraform/tenant';
export const PLAN_FILE = 'deploy.tfplan'; // *.tfplan is gitignored

export const imageRepo = (project: string, region: string) => `${region}-docker.pkg.dev/${project}/share-pages`;

/** gcloud prints `billingAccounts/XXXXXX-XXXXXX-XXXXXX`; null when unlinked or malformed. */
export function parseBilling(s: string): string | null {
  const id = s.trim().replace(/^billingAccounts\//, '');
  return /^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$/.test(id) ? id : null;
}

/**
 * Tracked files changed in `git status --porcelain` output that would make
 * the images differ from the commit they are tagged with. `.firebaserc` is
 * left out: `firebase target:apply` (the web part) writes Hosting targets
 * there on every deploy, and the images never contain it.
 */
export function blockingChanges(porcelain: string): string[] {
  return porcelain
    .split('\n')
    .filter((l) => l.trim() && !l.startsWith('??'))
    .map((l) => l.slice(3))
    .filter((path) => path !== '.firebaserc');
}

/** A step as a shell line, quoting arguments with spaces (for --dry-run and progress). */
export function shellLine(s: Step): string {
  const q = (a: string) => (/[\s'"$]/.test(a) ? `'${a.replace(/'/g, `'\\''`)}'` : a);
  const cmd = `${Object.entries(s.env ?? {}).map(([k, v]) => `${k}=${v} `).join('')}${s.argv.map(q).join(' ')}`;
  return s.cwd === '.' ? cmd : `(cd ${s.cwd} && ${cmd})`;
}

/** The parts to run, in order: an empty list means all of them. */
export function parseParts(list: string | undefined): Part[] {
  if (!list) return [...PARTS];
  const asked = list.split(',').map((s) => s.trim()).filter(Boolean);
  const bad = asked.filter((p) => !(PARTS as readonly string[]).includes(p));
  if (bad.length) throw new Error(`unknown part ${bad.join(', ')} (parts: ${PARTS.join(', ')})`);
  return PARTS.filter((p) => asked.includes(p));
}

export function deploySteps(i: DeployInputs): Step[] {
  const repo = imageRepo(i.project, i.region);
  const share = `${repo}/share-pages:${i.tag}`;
  const transcode = `${repo}/transcode-video:${i.tag}`;
  const p = ['--project', i.project];
  const steps: Step[] = [];
  const on = (part: Part) => i.parts.includes(part);

  if (on('functions')) {
    steps.push({ part: 'functions', title: 'Cloud Functions', argv: ['firebase', 'deploy', '--only', 'functions', ...p], cwd: '.', env: NODE_IPV4 });
  }
  if (on('images')) {
    steps.push(
      { part: 'images', title: 'Docker login for Artifact Registry', argv: ['gcloud', 'auth', 'configure-docker', `${i.region}-docker.pkg.dev`, '--quiet'], cwd: '.' },
      { part: 'images', title: 'Build the share pages image', argv: ['docker', 'build', '-f', 'apps/share_pages/Dockerfile', '--build-arg', `TENANT=${i.id}`, '-t', share, '.'], cwd: '.' },
      { part: 'images', title: 'Push the share pages image', argv: ['docker', 'push', share], cwd: '.' },
      { part: 'images', title: 'Build the video transcoder image', argv: ['docker', 'build', '-f', 'transcode.Dockerfile', '-t', transcode, '.'], cwd: 'functions' },
      { part: 'images', title: 'Push the video transcoder image', argv: ['docker', 'push', transcode], cwd: '.' },
    );
  }
  if (on('infra')) {
    if (!i.billing) throw new Error('infra needs the billing account');
    const vars = ['-var', `tenant_id=${i.id}`, '-var', `env=${i.env}`, '-var', `billing_account=${i.billing}`, '-var', `share_pages_image=${share}`, '-var', `transcode_image=${transcode}`];
    // Identity Platform refuses user credentials without a quota project (README).
    const quota = { GOOGLE_BILLING_PROJECT: i.project, USER_PROJECT_OVERRIDE: 'true' };
    if (!on('images')) {
      // Built earlier from the same commit? Fail before Terraform points Cloud Run at a missing image.
      for (const img of [share, transcode]) {
        steps.push({ part: 'infra', title: `Check ${img.split('/').pop()} exists`, argv: ['gcloud', 'artifacts', 'docker', 'images', 'describe', img, '--quiet'], cwd: '.' });
      }
    }
    steps.push(
      { part: 'infra', title: 'Terraform init', argv: ['terraform', 'init', '-reconfigure', `-backend-config=prefix=${i.id}/${i.env}`], cwd: TF_DIR },
      { part: 'infra', title: 'Terraform plan', argv: ['terraform', 'plan', `-out=${PLAN_FILE}`, ...vars], cwd: TF_DIR, env: quota },
      { part: 'infra', title: 'Check the plan', argv: ['terraform', 'show', '-json', PLAN_FILE], cwd: TF_DIR, checkPlan: true },
      { part: 'infra', title: 'Terraform apply', argv: ['terraform', 'apply', PLAN_FILE], cwd: TF_DIR, env: quota },
    );
  }
  if (on('web')) {
    const node = ['node', 'tools/tenant-cli/src/cli.ts'];
    steps.push(
      { part: 'web', title: 'Tenant assets for the app and the admin', argv: [...node, 'prepare', i.id], cwd: '.' },
      { part: 'web', title: 'Admin web shell (first time only)', argv: ['sh', '-c', 'flutter create . --platforms=web --project-name realtor_admin && rm -f test/widget_test.dart'], cwd: 'apps/admin', skipIfExists: 'apps/admin/web/index.html' },
      { part: 'web', title: 'Build the admin', argv: ['flutter', 'build', 'web', '--release'], cwd: 'apps/admin' },
      { part: 'web', title: 'App web shell (first time only)', argv: ['flutter', 'create', '.', '--platforms=web', '--project-name', 'realtor_app'], cwd: 'apps/realtor_app', skipIfExists: 'apps/realtor_app/web/index.html' },
      { part: 'web', title: "App web shell: the tenant's title, colours and previews", argv: [...node, 'web', i.id], cwd: '.' },
      { part: 'web', title: 'Build the customer app', argv: ['flutter', 'build', 'web', '--release', '--wasm'], cwd: 'apps/realtor_app' },
    );
    for (const site of ['admin', 'app', 'share']) {
      steps.push({ part: 'web', title: `Hosting target ${site}`, argv: ['firebase', 'target:apply', 'hosting', site, `${i.project}-${site}`, ...p], cwd: '.' });
    }
    steps.push({ part: 'web', title: 'Hosting: admin, app and share sites', argv: ['firebase', 'deploy', '--only', 'hosting:admin,hosting:app,hosting:share', ...p], cwd: '.', env: NODE_IPV4 });
  }
  return steps;
}

/** The parts of `terraform show -json` that the check reads. */
interface PlanJson {
  resource_changes?: {
    address: string;
    type: string;
    change: { actions: string[]; before?: Record<string, unknown> | null; after?: Record<string, unknown> | null };
  }[];
}

/**
 * Why a saved plan must not be applied; empty when it may. Refuses:
 * - removing or changing the project's billing account;
 * - deleting anything outright (replacing a rules release or ruleset is fine);
 * - any Cloud Run image outside this project's repo (the empty-variable case).
 */
export function planProblems(plan: PlanJson, repo: string): string[] {
  const out: string[] = [];
  for (const rc of plan.resource_changes ?? []) {
    const { actions, before, after } = rc.change;
    if (actions.length === 1 && actions[0] === 'delete') out.push(`${rc.address} would be deleted`);
    if (rc.type === 'google_project' && before && after && before.billing_account !== after.billing_account) {
      out.push(`${rc.address}: billing account ${before.billing_account ?? 'none'} → ${after.billing_account ?? 'none'}`);
    }
    if (after && rc.type.startsWith('google_cloud_run_v2_')) {
      for (const image of imagesIn(after)) {
        if (!image.startsWith(`${repo}/`)) out.push(`${rc.address}: image "${image}" is not in ${repo}`);
      }
    }
  }
  return out;
}

/** Every `image` string anywhere under [v] (Cloud Run nests it in template.containers). */
function imagesIn(v: unknown): string[] {
  if (Array.isArray(v)) return v.flatMap(imagesIn);
  if (v && typeof v === 'object') {
    return Object.entries(v).flatMap(([k, x]) => (k === 'image' && typeof x === 'string' ? [x] : imagesIn(x)));
  }
  return [];
}

/** Counts of what the plan does, for the confirmation prompt (replace = destroy and create). */
export function planSummary(plan: PlanJson): { add: number; change: number; replace: number; destroy: number } {
  const s = { add: 0, change: 0, replace: 0, destroy: 0 };
  for (const rc of plan.resource_changes ?? []) {
    const a = rc.change.actions.join(',');
    if (a === 'create') s.add++;
    else if (a === 'update') s.change++;
    else if (a === 'delete') s.destroy++;
    else if (a.includes('delete') && a.includes('create')) s.replace++;
  }
  return s;
}
