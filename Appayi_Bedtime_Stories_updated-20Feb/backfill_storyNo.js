const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

function toDate(v, fallback) {
  if (!v) return fallback;
  // Firestore Timestamp
  if (typeof v.toDate === "function") return v.toDate();
  // millis
  if (typeof v === "number") return new Date(v);
  // ISO string
  if (typeof v === "string") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? fallback : d;
  }
  return fallback;
}

function toInt(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === "number") return Math.trunc(v);
  const n = parseInt(String(v).trim(), 10);
  return Number.isFinite(n) ? n : null;
}

async function run() {
  const snap = await db.collection("stories").get();

  const items = snap.docs.map((doc) => {
    const data = doc.data();

    // accept old keys too (if your script used different names)
    const rawNo =
      data.storyNo ??
      data.story_no ??
      data.storyNumber ??
      data.storyIndex ??
      null;

    const createdFallback = doc.createTime ? doc.createTime.toDate() : new Date(0);
    const createdAt = toDate(data.createdAt, createdFallback);

    return {
      ref: doc.ref,
      createdAt,
      existingNo: toInt(rawNo),
    };
  });

  // sort by upload time (oldest first)
  items.sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());

  let batch = db.batch();
  let ops = 0;
  let seq = 0;

  for (const it of items) {
    seq += 1;

    // If existingNo is valid, keep it; otherwise assign sequential
    // (If you want to FORCE overwrite everything, use: const finalNo = seq;)
    const finalNo = it.existingNo ?? seq;

    batch.set(it.ref, { storyNo: finalNo }, { merge: true });
    ops += 1;

    // commit every ~450 writes (limit is 500)
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();

  // update the counter too (optional but recommended)
  await db.collection("meta").doc("storyCounter").set({ next: seq }, { merge: true });

  console.log(`✅ Done. Updated ${seq} stories with storyNo.`);
}

run().catch((e) => {
  console.error("❌ Failed:", e);
  process.exit(1);
});
