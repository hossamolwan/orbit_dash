const { google } = require('googleapis');
const { getApps, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { defineString } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions/logger');

const {
  GEM_PRODUCTS,
  PURCHASE_STATES,
  classifyVerifiedPurchase,
  obfuscatedAccountIdForUid,
  parsePurchaseRequest,
  transactionIdForToken,
} = require('./purchase_contract');

const playPackageName = defineString('PLAY_PACKAGE_NAME', { default: '' });
const androidPublisherScope =
  'https://www.googleapis.com/auth/androidpublisher';
const maxPaidGemBalance = 2147483647;

if (getApps().length === 0) initializeApp();
const db = getFirestore();

function purchaseRef(transactionId) {
  return db.collection('gemPurchaseTransactions').doc(transactionId);
}

function walletRef(uid) {
  return db.collection('players').doc(uid).collection('economy').doc('gems');
}

function validateExistingTransaction(data, uid, productId) {
  if (data.playerUid !== uid || data.productId !== productId) {
    throw new HttpsError(
      'failed-precondition',
      'This purchase is bound to a different account or product.',
    );
  }
}

async function verifyWithGooglePlay(packageName, productId, token) {
  const auth = new google.auth.GoogleAuth({ scopes: [androidPublisherScope] });
  const publisher = google.androidpublisher({ version: 'v3', auth });
  const response = await publisher.purchases.productsv2.getproductpurchasev2({
    packageName,
    token,
  });
  return response.data;
}

async function storeNonGrantOutcome({
  transactionId,
  uid,
  productId,
  state,
  failureCode,
}) {
  const ref = purchaseRef(transactionId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const existing = snapshot.data();
    if (existing) {
      validateExistingTransaction(existing, uid, productId);
      if (
        existing.state === PURCHASE_STATES.fulfilled ||
        existing.state === PURCHASE_STATES.fulfilledPendingConsumption
      ) {
        return existing;
      }
      if (existing.state === PURCHASE_STATES.rejected) return existing;
    }
    const now = FieldValue.serverTimestamp();
    transaction.set(
      ref,
      {
        transactionId,
        playerUid: uid,
        productId,
        purchaseTokenHash: transactionId,
        state,
        gemQuantityGranted: 0,
        verifiedAt: state === PURCHASE_STATES.pending ? null : now,
        fulfilledAt: null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        lastAttemptAt: now,
        attemptCount: (existing?.attemptCount ?? 0) + 1,
        lastFailureCode: failureCode,
      },
      { merge: true },
    );
    return { state, gemQuantityGranted: 0 };
  });
}

async function fulfillVerifiedPurchase({
  transactionId,
  uid,
  productId,
}) {
  const gemQuantity = GEM_PRODUCTS[productId];
  const ref = purchaseRef(transactionId);
  const balanceDocument = walletRef(uid);
  return db.runTransaction(async (transaction) => {
    const purchaseSnapshot = await transaction.get(ref);
    const existing = purchaseSnapshot.data();
    if (existing) {
      validateExistingTransaction(existing, uid, productId);
      if (
        existing.state === PURCHASE_STATES.fulfilled ||
        existing.state === PURCHASE_STATES.fulfilledPendingConsumption ||
        existing.state === PURCHASE_STATES.rejected
      ) {
        return existing;
      }
    }

    const balanceSnapshot = await transaction.get(balanceDocument);
    const rawBalance = balanceSnapshot.data()?.paidBalance ?? 0;
    if (!Number.isSafeInteger(rawBalance) || rawBalance < 0) {
      throw new HttpsError(
        'failed-precondition',
        'The server-side gem balance is invalid.',
      );
    }
    const nextBalance = rawBalance + gemQuantity;
    if (nextBalance > maxPaidGemBalance) {
      throw new HttpsError(
        'resource-exhausted',
        'The server-side gem balance limit would be exceeded.',
      );
    }

    const now = FieldValue.serverTimestamp();
    transaction.set(
      balanceDocument,
      { paidBalance: nextBalance, updatedAt: now },
      { merge: true },
    );
    transaction.set(
      ref,
      {
        transactionId,
        playerUid: uid,
        productId,
        purchaseTokenHash: transactionId,
        state: PURCHASE_STATES.fulfilledPendingConsumption,
        verifiedAt: now,
        fulfilledAt: now,
        gemQuantityGranted: gemQuantity,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        lastAttemptAt: now,
        attemptCount: (existing?.attemptCount ?? 0) + 1,
        lastFailureCode: null,
      },
      { merge: true },
    );
    return {
      state: PURCHASE_STATES.fulfilledPendingConsumption,
      gemQuantityGranted: gemQuantity,
    };
  });
}

async function markConsumed(transactionId, uid, productId) {
  const ref = purchaseRef(transactionId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const purchase = snapshot.data();
    if (!purchase) {
      throw new HttpsError('not-found', 'Purchase transaction was not found.');
    }
    validateExistingTransaction(purchase, uid, productId);
    if (purchase.state === PURCHASE_STATES.fulfilled) return purchase;
    if (purchase.state !== PURCHASE_STATES.fulfilledPendingConsumption) {
      return purchase;
    }
    transaction.update(ref, {
      state: PURCHASE_STATES.fulfilled,
      consumedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastFailureCode: null,
    });
    return {
      ...purchase,
      state: PURCHASE_STATES.fulfilled,
    };
  });
}

async function noteConsumptionFailure(transactionId) {
  try {
    const ref = purchaseRef(transactionId);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const purchase = snapshot.data();
      if (
        !purchase ||
        purchase.state !== PURCHASE_STATES.fulfilledPendingConsumption
      ) {
        return;
      }
      transaction.update(ref, {
        updatedAt: FieldValue.serverTimestamp(),
        lastAttemptAt: FieldValue.serverTimestamp(),
        lastFailureCode: 'play_consumption_unavailable',
      });
    });
  } catch (_) {
    // The durable fulfillment record is already committed. A later retry can
    // inspect Play's consumption state and safely finish this bookkeeping.
  }
}

async function noteVerificationFailure(transactionId, uid, productId) {
  const ref = purchaseRef(transactionId);
  try {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const purchase = snapshot.data();
      if (!purchase) return;
      validateExistingTransaction(purchase, uid, productId);
      if (
        purchase.state === PURCHASE_STATES.fulfilled ||
        purchase.state === PURCHASE_STATES.fulfilledPendingConsumption ||
        purchase.state === PURCHASE_STATES.rejected
      ) {
        return;
      }
      transaction.update(ref, {
        updatedAt: FieldValue.serverTimestamp(),
        lastAttemptAt: FieldValue.serverTimestamp(),
        attemptCount: (purchase.attemptCount ?? 0) + 1,
        lastFailureCode: 'play_verification_unavailable',
      });
    });
  } catch (_) {
    // Verification remains fail-closed even if diagnostic persistence fails.
  }
}

async function consumeIfNeeded({
  packageName,
  productId,
  token,
  transactionId,
  uid,
  purchase,
}) {
  try {
    let alreadyConsumed = purchase.alreadyConsumed;
    if (!alreadyConsumed) {
      const response = await verifyWithGooglePlay(
        packageName,
        productId,
        token,
      );
      const checked = classifyVerifiedPurchase(
        response,
        productId,
        obfuscatedAccountIdForUid(uid),
      );
      if (checked.outcome !== 'purchased') {
        await noteConsumptionFailure(transactionId);
        return purchase;
      }
      alreadyConsumed = checked.alreadyConsumed;
    }
    if (!alreadyConsumed) {
      const auth = new google.auth.GoogleAuth({
        scopes: [androidPublisherScope],
      });
      const publisher = google.androidpublisher({ version: 'v3', auth });
      await publisher.purchases.products.consume({
        packageName,
        productId,
        token,
      });
    }
    return await markConsumed(transactionId, uid, productId);
  } catch (_) {
    await noteConsumptionFailure(transactionId);
    return purchase;
  }
}

exports.verifyAndFulfillGemPurchase = onCall(
  { enforceAppCheck: true, maxInstances: 5 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Sign-in is required.');
    }
    const parsed = parsePurchaseRequest(request.data);
    if (!parsed) {
      throw new HttpsError(
        'invalid-argument',
        'A known product ID and valid purchase token are required.',
      );
    }

    const uid = request.auth.uid;
    const { productId, purchaseToken } = parsed;
    const transactionId = transactionIdForToken(purchaseToken);
    const ref = purchaseRef(transactionId);
    const previousSnapshot = await ref.get();
    const previous = previousSnapshot.data();
    if (previous) {
      validateExistingTransaction(previous, uid, productId);
      if (previous.state === PURCHASE_STATES.rejected) {
        throw new HttpsError(
          'failed-precondition',
          'This purchase was rejected by Google Play verification.',
        );
      }
      if (previous.state === PURCHASE_STATES.fulfilled) {
        return {
          transactionId,
          state: previous.state,
          gemQuantityGranted: previous.gemQuantityGranted,
        };
      }
    }

    const packageName = playPackageName.value().trim();
    if (!packageName) {
      throw new HttpsError(
        'failed-precondition',
        'Google Play verification is not configured.',
      );
    }

    let verified;
    try {
      const playPurchase = await verifyWithGooglePlay(
        packageName,
        productId,
        purchaseToken,
      );
      verified = classifyVerifiedPurchase(
        playPurchase,
        productId,
        obfuscatedAccountIdForUid(uid),
      );
    } catch (_) {
      await noteVerificationFailure(transactionId, uid, productId);
      logger.warn('Google Play purchase verification unavailable.', {
        transactionId,
        productId,
      });
      throw new HttpsError(
        'unavailable',
        'Google Play verification is temporarily unavailable.',
      );
    }

    if (verified.outcome === 'invalid') {
      throw new HttpsError(
        'permission-denied',
        'Google Play purchase details do not match this account and product.',
      );
    }
    if (verified.outcome === 'pending') {
      const pending = await storeNonGrantOutcome({
        transactionId,
        uid,
        productId,
        state: PURCHASE_STATES.pending,
        failureCode: 'play_purchase_pending',
      });
      return {
        transactionId,
        state: pending.state,
        gemQuantityGranted: 0,
      };
    }
    if (verified.outcome === 'cancelled') {
      await storeNonGrantOutcome({
        transactionId,
        uid,
        productId,
        state: PURCHASE_STATES.rejected,
        failureCode: 'play_purchase_cancelled',
      });
      throw new HttpsError(
        'failed-precondition',
        'Google Play reports that this purchase was canceled.',
      );
    }

    const result = await fulfillVerifiedPurchase({
      transactionId,
      uid,
      productId,
    });
    if (result.state === PURCHASE_STATES.rejected) {
      throw new HttpsError(
        'failed-precondition',
        'This purchase cannot be fulfilled.',
      );
    }
    const settled = await consumeIfNeeded({
      packageName,
      productId,
      token: purchaseToken,
      transactionId,
      uid,
      purchase: {
        ...result,
        alreadyConsumed: verified.alreadyConsumed,
      },
    });
    return {
      transactionId,
      state: settled.state,
      gemQuantityGranted: settled.gemQuantityGranted,
    };
  },
);
