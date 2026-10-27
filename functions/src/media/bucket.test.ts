import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mediaBucketName } from './bucket';

test('the media bucket is the one Terraform names after the project', () => {
  assert.equal(mediaBucketName({ GCLOUD_PROJECT: 'acme-realty-dev' }), 'acme-realty-dev-media');
  assert.equal(mediaBucketName({ FIREBASE_CONFIG: JSON.stringify({ projectId: 'acme-realty-prod' }) }), 'acme-realty-prod-media');
});

test('no project id is a clear error, not a guess', () => {
  assert.throws(() => mediaBucketName({}), /project id/);
  assert.throws(() => mediaBucketName({ FIREBASE_CONFIG: 'not json' }), /project id/);
});
