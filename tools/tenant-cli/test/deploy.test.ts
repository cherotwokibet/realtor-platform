import { test } from 'node:test';
import assert from 'node:assert/strict';
import { blockingChanges, deploySteps, imageRepo, parseBilling, shellLine, parseParts, planProblems, planSummary } from '../src/deploy.ts';

const base = { id: 'acme', env: 'dev' as const, project: 'acme-dev', region: 'europe-west1', tag: 'abc1234', billing: 'ABCDEF-123456-0A1B2C' };
const repo = imageRepo('acme-dev', 'europe-west1');

test('billing account from gcloud output, or null', () => {
  assert.equal(parseBilling('billingAccounts/ABCDEF-123456-0A1B2C\n'), 'ABCDEF-123456-0A1B2C');
  assert.equal(parseBilling('ABCDEF-123456-0A1B2C'), 'ABCDEF-123456-0A1B2C');
  assert.equal(parseBilling(''), null); // unlinked project
  assert.equal(parseBilling('billingAccounts/'), null);
  assert.equal(parseBilling('$BILLING'), null);
});

test('parts: all by default, in deploy order, unknown ones refused', () => {
  assert.deepEqual(parseParts(undefined), ['functions', 'images', 'infra', 'web']);
  assert.deepEqual(parseParts('web,functions'), ['functions', 'web']);
  assert.throws(() => parseParts('functions,hosting'), /unknown part hosting/);
});

test('images and Terraform use the same full image names', () => {
  const steps = deploySteps({ ...base, parts: ['images', 'infra'] });
  const share = `${repo}/share-pages:abc1234`;
  const transcode = `${repo}/transcode-video:abc1234`;
  assert.ok(steps.some((s) => s.argv.join(' ') === `docker push ${share}`));
  assert.ok(steps.some((s) => s.argv.join(' ') === `docker push ${transcode}`));
  const plan = steps.find((s) => s.title === 'Terraform plan')!;
  for (const v of ['tenant_id=acme', 'env=dev', 'billing_account=ABCDEF-123456-0A1B2C', `share_pages_image=${share}`, `transcode_image=${transcode}`]) {
    assert.ok(plan.argv.includes(v), v);
  }
  assert.equal(plan.env?.GOOGLE_BILLING_PROJECT, 'acme-dev');
  // Apply runs the checked plan, never a fresh one.
  assert.deepEqual(steps.at(-1)!.argv, ['terraform', 'apply', 'deploy.tfplan']);
  assert.ok(steps.at(-2)!.checkPlan);
  // Images were just pushed, so no existence check.
  assert.ok(!steps.some((s) => s.argv.includes('describe')));
});

test('infra alone checks the images exist first, and needs the billing account', () => {
  const steps = deploySteps({ ...base, parts: ['infra'] });
  assert.deepEqual(
    steps.filter((s) => s.argv.includes('describe')).map((s) => s.argv[5]),
    [`${repo}/share-pages:abc1234`, `${repo}/transcode-video:abc1234`],
  );
  assert.equal(steps.findIndex((s) => s.argv.includes('describe')), 0);
  assert.throws(() => deploySteps({ ...base, billing: undefined, parts: ['infra'] }), /billing/);
});

test('web: one-time shells are skippable, all three sites deploy', () => {
  const steps = deploySteps({ ...base, parts: ['web'] });
  assert.deepEqual(
    steps.filter((s) => s.skipIfExists).map((s) => s.skipIfExists),
    ['apps/admin/web/index.html', 'apps/realtor_app/web/index.html'],
  );
  assert.ok(steps.some((s) => s.argv.join(' ') === 'firebase target:apply hosting app acme-dev-app --project acme-dev'));
  const last = steps.at(-1)!;
  assert.deepEqual(last.argv, ['firebase', 'deploy', '--only', 'hosting:admin,hosting:app,hosting:share', '--project', 'acme-dev']);
  assert.match(last.env!.NODE_OPTIONS, /ipv4first/);
  assert.ok(!steps.some((s) => s.part !== 'web'));
});

const run = (image: string) => ({ template: [{ containers: [{ image }] }] });

test('a normal plan passes: replacing rules and moving to a new image', () => {
  const plan = {
    resource_changes: [
      { address: 'module.env.google_firebaserules_ruleset.firestore', type: 'google_firebaserules_ruleset', change: { actions: ['delete', 'create'], before: {}, after: {} } },
      { address: 'module.env.google_cloud_run_v2_service.share_pages[0]', type: 'google_cloud_run_v2_service', change: { actions: ['update'], before: run(`${repo}/share-pages:old`), after: run(`${repo}/share-pages:abc1234`) } },
      { address: 'module.env.google_project.this', type: 'google_project', change: { actions: ['no-op'], before: { billing_account: 'ABCDEF-123456-0A1B2C' }, after: { billing_account: 'ABCDEF-123456-0A1B2C' } } },
      { address: 'module.env.google_firestore_index.composite["x"]', type: 'google_firestore_index', change: { actions: ['create'], before: null, after: {} } },
    ],
  };
  assert.deepEqual(planProblems(plan, repo), []);
  assert.deepEqual(planSummary(plan), { add: 1, change: 1, replace: 1, destroy: 0 });
});

test('the empty-variable plan is refused: billing unlinked, image outside the repo', () => {
  const plan = {
    resource_changes: [
      { address: 'module.env.google_project.this', type: 'google_project', change: { actions: ['update'], before: { billing_account: 'ABCDEF-123456-0A1B2C' }, after: { billing_account: null } } },
      { address: 'module.env.google_cloud_run_v2_service.share_pages[0]', type: 'google_cloud_run_v2_service', change: { actions: ['update'], before: run(`${repo}/share-pages:old`), after: run('/share-pages:abc1234') } },
      { address: 'module.env.google_cloud_run_v2_job.transcode[0]', type: 'google_cloud_run_v2_job', change: { actions: ['create'], before: null, after: run('/transcode-video:abc1234') } },
    ],
  };
  const problems = planProblems(plan, repo);
  assert.equal(problems.length, 3);
  assert.match(problems[0], /billing account ABCDEF-123456-0A1B2C → none/);
  assert.match(problems[1], /"\/share-pages:abc1234" is not in/);
  assert.match(problems[2], /transcode/);
});

test('an outright delete is refused', () => {
  const plan = {
    resource_changes: [{ address: 'module.env.google_storage_bucket.media', type: 'google_storage_bucket', change: { actions: ['delete'], before: {}, after: null } }],
  };
  assert.deepEqual(planProblems(plan, repo), ['module.env.google_storage_bucket.media would be deleted']);
});

test('uncommitted changes that block images: tracked files only, never .firebaserc', () => {
  const porcelain = [' M .firebaserc', ' D apps/realtor_app/test/widget_test.dart', '?? infra/terraform/tenant/deploy.tfplan', 'M  functions/src/index.ts', ''].join('\n');
  assert.deepEqual(blockingChanges(porcelain), ['apps/realtor_app/test/widget_test.dart', 'functions/src/index.ts']);
  assert.deepEqual(blockingChanges(' M .firebaserc\n'), []);
  assert.deepEqual(blockingChanges(''), []);
});

test('steps print as shell lines a person could paste', () => {
  const steps = deploySteps({ ...base, parts: ['web'] });
  assert.equal(
    shellLine(steps.find((s) => s.cwd === 'apps/admin' && s.skipIfExists)!),
    "(cd apps/admin && sh -c 'flutter create . --platforms=web --project-name realtor_admin && rm -f test/widget_test.dart')",
  );
  assert.equal(shellLine(steps.at(-1)!), 'NODE_OPTIONS=--dns-result-order=ipv4first firebase deploy --only hosting:admin,hosting:app,hosting:share --project acme-dev');
});
