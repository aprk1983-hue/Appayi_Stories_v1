const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

function toDate(v, fallback) {
  if (!v) return fallback;
  if (typeof v.toDate === "function") return v.toDate(); // Timestamp
  if (typeof v === "number") return new Date(v);         // millis
  if (typeof v === "string") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? fallback : d;
  }
  return fallback;
}

function normLangLower(v) {
  const s = (v ?? "un").toString().trim().toLowerCase();
  return s.length ? s : "un";
}

async function run() {
  const snap = await db.collection("stories").get();

  const groups = new Map(); // lang -> array of {ref, createdAt}
  snap.docs.forEach((doc) => {
    const data = doc.data();
    const lang = normLangLower(data.language);
    const createdFallback = doc.createTime ? doc.createTime.toDate() : new Date(0);
    const createdAt = toDate(data.createdAt, createdFallback);

    if (!groups.has(lang)) groups.set(lang, []);
    groups.get(lang).push({ ref: doc.ref, createdAt });
  });

  let totalUpdated = 0;

  for (const [lang, items] of groups.entries()) {
    items.sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());

    let batch = db.batch();
    let ops = 0;

    for (let i = 0; i < items.length; i++) {
      const storyNo = i + 1;
      batch.set(items[i].ref, { storyNo, language: lang }, { merge: true });
      ops++;
      totalUpdated++;

      if (ops >= 450) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    if (ops > 0) await batch.commit();

    // per-language counter in lowercase
    await db.collection("meta").doc(`storyCounter_${lang}`).set(
      { next: items.length },
      { merge: true }
    );

    console.log(`✅ ${lang}: updated ${items.length} stories (storyNo 1..${items.length})`);
  }

  console.log(`✅ Done. Updated total ${totalUpdated} stories.`);
}

run().catch((e) => {
  console.error("❌ Failed:", e);
  process.exit(1);
});
