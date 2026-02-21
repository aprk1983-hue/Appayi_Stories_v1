/**
 * Firebase Cloud Function (Firestore trigger) to automatically set:
 * - createdAt (serverTimestamp) if missing
 * - updatedAt (serverTimestamp)
 * - shareId (numeric, sequential) if missing, using a counter doc in transaction
 *
 * IMPORTANT:
 * - Adjust the collection path if your collection differs.
 * - Set STARTING_SHARE_ID to the next number after your highest existing shareId.
 *
 * Deploy with:
 *   firebase deploy --only functions
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const COLLECTION_PATH = "stories/{storyDocId}"; // <-- change if needed
const COUNTER_DOC_PATH = "counters/stories_shareId";
const STARTING_SHARE_ID = 114; // <-- set to next id after max (example: after 113)

exports.autoFillStoryFields = onDocumentCreated(COLLECTION_PATH, async (event) => {
  const snap = event.data;
  if (!snap) return;

  const ref = snap.ref;
  const data = snap.data() || {};

  const needsCreatedAt = !Object.prototype.hasOwnProperty.call(data, "createdAt");
  const rawShareId = data.shareId;
  const needsShareId =
    !Object.prototype.hasOwnProperty.call(data, "shareId") ||
    rawShareId === null ||
    String(rawShareId).trim() === "";

  // If nothing needed, exit.
  if (!needsCreatedAt && !needsShareId) return;

  // Always set updatedAt
  const baseUpdates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (needsCreatedAt) {
    baseUpdates.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  // If shareId missing, allocate via counter doc in one transaction.
  if (needsShareId) {
    const counterRef = db.doc(COUNTER_DOC_PATH);

    await db.runTransaction(async (tx) => {
      const counterSnap = await tx.get(counterRef);

      let next;
      if (counterSnap.exists) {
        const v = counterSnap.data()?.nextShareId;
        next = (typeof v === "number" ? v : Number(v));
        if (!Number.isFinite(next) || next <= 0) next = STARTING_SHARE_ID;
      } else {
        next = STARTING_SHARE_ID;
      }

      // Update story doc
      tx.update(ref, { ...baseUpdates, shareId: next });

      // Increment counter
      tx.set(counterRef, { nextShareId: next + 1 }, { merge: true });
    });

    return;
  }

  // Only createdAt/updatedAt missing
  await ref.update(baseUpdates);
});
