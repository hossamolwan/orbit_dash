const { createHash } = require('node:crypto');

// IDs follow the existing Gem package catalog; grants include bonuses.
const GEM_PRODUCTS = Object.freeze({
  'gems.small': 500,
  'gems.medium': 1300,
  'gems.large': 2850,
  'gems.mega': 7200,
});

const PURCHASE_STATES = Object.freeze({
  pending: 'pending',
  fulfilledPendingConsumption: 'fulfilled_pending_consumption',
  fulfilled: 'fulfilled',
  rejected: 'rejected',
});

function parsePurchaseRequest(data) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    return null;
  }
  const { productId, purchaseToken } = data;
  if (
    typeof productId !== 'string' ||
    !Object.hasOwn(GEM_PRODUCTS, productId) ||
    typeof purchaseToken !== 'string' ||
    purchaseToken.trim().length === 0 ||
    purchaseToken.length > 4096
  ) {
    return null;
  }
  return { productId, purchaseToken };
}

function transactionIdForToken(token) {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

// Sent in Play Billing's obfuscated account ID field by a future client.
function obfuscatedAccountIdForUid(uid) {
  return createHash('sha256').update(uid, 'utf8').digest('hex');
}

function classifyVerifiedPurchase(data, expectedProductId, expectedAccountId) {
  const state = data?.purchaseStateContext?.purchaseState;
  const items = data?.productLineItem;
  const item = Array.isArray(items) && items.length === 1 ? items[0] : null;
  const productId = item?.productId;
  const accountId = data?.obfuscatedExternalAccountId;
  const quantity = item?.productOfferDetails?.quantity ?? 1;

  if (
    productId !== expectedProductId ||
    accountId !== expectedAccountId ||
    quantity !== 1
  ) {
    return { outcome: 'invalid' };
  }
  if (state === 'PENDING') return { outcome: 'pending' };
  if (state === 'CANCELLED') return { outcome: 'cancelled' };
  if (state !== 'PURCHASED') return { outcome: 'invalid' };

  return {
    outcome: 'purchased',
    productId,
    alreadyConsumed:
      item.productOfferDetails?.consumptionState ===
      'CONSUMPTION_STATE_CONSUMED',
  };
}

module.exports = {
  GEM_PRODUCTS,
  PURCHASE_STATES,
  classifyVerifiedPurchase,
  obfuscatedAccountIdForUid,
  parsePurchaseRequest,
  transactionIdForToken,
};
