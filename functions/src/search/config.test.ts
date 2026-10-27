import { test } from 'node:test';
import assert from 'node:assert/strict';
import { searchConfig } from './config';

test('search is off until both TENANT_ID and TYPESENSE_HOST are set', () => {
  assert.equal(searchConfig({}), null);
  assert.equal(searchConfig({ TENANT_ID: 'acme-realty' }), null);
  assert.equal(searchConfig({ TYPESENSE_HOST: 'xyz.a1.typesense.net' }), null);
  assert.equal(searchConfig({ TENANT_ID: ' ', TYPESENSE_HOST: ' ' }), null);
  assert.deepEqual(searchConfig({ TENANT_ID: 'acme-realty', TYPESENSE_HOST: ' xyz.a1.typesense.net ' }), {
    tenantId: 'acme-realty',
    host: 'xyz.a1.typesense.net',
  });
});

test('a mistyped value fails the deploy loudly instead of syncing nowhere', () => {
  assert.throws(() => searchConfig({ TENANT_ID: 'Acme Realty', TYPESENSE_HOST: 'xyz.a1.typesense.net' }), /TENANT_ID/);
  assert.throws(() => searchConfig({ TENANT_ID: 'acme-realty', TYPESENSE_HOST: 'https://xyz.a1.typesense.net' }), /TYPESENSE_HOST/);
});
