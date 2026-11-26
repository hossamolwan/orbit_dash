const test = require('node:test');
const assert = require('node:assert/strict');

const {
  GEM_PRODUCTS,
  PURCHASE_STATES,
  classifyVerifiedPurchase,
  obfuscatedAccountIdForUid,
  parsePurchaseRequest,
  transactionIdForToken,
} = require('../src/purchase_contract');

test('server catalog uses stable IDs and includes package bonuses', () => {
  assert.deepEqual(GEM_PRODUCTS, {
    'gems.small': 500,
    'gems.medium': 1300,
    'gems.large': 2850,
    'gems.mega': 7200,
  });
});

test('request accepts known product IDs and ignores client grant quantities', () => {
  assert.deepEqual(
    parsePurchaseRequest({
      productId: 'gems.small',
      purchaseToken: 'play-token',
      gems: 999999,
      bonusGems: 999999,
    }),
    { productId: 'gems.small', purchaseToken: 'play-token' },
  );
  assert.equal(
    parsePurchaseRequest({ productId: 'unknown', purchaseToken: 'token' }),
    null,
  );
  assert.equal(
    parsePurchaseRequest({ productId: 'gems.small', purchaseToken: '  ' }),
    null,
  );
  assert.equal(
    parsePurchaseRequest({
      productId: 'gems.small',
      purchaseToken: 't'.repeat(4097),
    }),
    null,
  );
});

test('purchase token hashes are stable and do not expose the token', () => {
  const id = transactionIdForToken('play-token');
  assert.equal(id, transactionIdForToken('play-token'));
  assert.match(id, /^[a-f0-9]{64}$/);
  assert.notEqual(id, 'play-token');
});

test('account binding uses a stable obfuscated Firebase UID', () => {
  assert.equal(
    obfuscatedAccountIdForUid('firebase-uid'),
    obfuscatedAccountIdForUid('firebase-uid'),
  );
  assert.notEqual(
    obfuscatedAccountIdForUid('firebase-uid'),
    obfuscatedAccountIdForUid('other-uid'),
  );
});

test('verified purchase classification rejects pending and mismatched data', () => {
  const accountId = obfuscatedAccountIdForUid('firebase-uid');
  const data = {
    purchaseStateContext: { purchaseState: 'PURCHASED' },
    productLineItem: [{ productId: 'gems.small' }],
    obfuscatedExternalAccountId: accountId,
  };
  assert.equal(
    classifyVerifiedPurchase(data, 'gems.small', accountId).outcome,
    'purchased',
  );
  assert.deepEqual(
    classifyVerifiedPurchase(
      { ...data, purchaseStateContext: { purchaseState: 'PENDING' } },
      'gems.small',
      accountId,
    ),
    { outcome: 'pending' },
  );
  assert.equal(
    classifyVerifiedPurchase(data, 'gems.medium', accountId).outcome,
    'invalid',
  );
  assert.equal(
    classifyVerifiedPurchase(data, 'gems.small', 'wrong-account').outcome,
    'invalid',
  );
  assert.equal(
    classifyVerifiedPurchase(
      {
        ...data,
        productLineItem: [
          {
            productId: 'gems.small',
            productOfferDetails: { quantity: 2 },
          },
        ],
      },
      'gems.small',
      accountId,
    ).outcome,
    'invalid',
  );
});

test('purchase states are explicit and stable', () => {
  assert.deepEqual(PURCHASE_STATES, {
    pending: 'pending',
    fulfilledPendingConsumption: 'fulfilled_pending_consumption',
    fulfilled: 'fulfilled',
    rejected: 'rejected',
  });
});
