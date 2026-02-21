const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const COLLECTION_PATH = "stories/{storyDocId}";
const COUNTER_DOC_PATH = "counters/stories_shareId";
const STARTING_SHARE_ID = 114;

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

  if (!needsCreatedAt && !needsShareId) return;

  const baseUpdates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (needsCreatedAt) {
    baseUpdates.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

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

      tx.update(ref, { ...baseUpdates, shareId: next });
      tx.set(counterRef, { nextShareId: next + 1 }, { merge: true });
    });

    return;
  }

  await ref.update(baseUpdates);
});
