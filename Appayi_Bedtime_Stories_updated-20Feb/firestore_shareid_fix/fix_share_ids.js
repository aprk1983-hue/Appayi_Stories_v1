/**
 * Firestore shareId audit + fix (createdAt-based) + reporting
 *
 * What it does:
 * - Reads all docs in a collection (default: "stories")
 * - Reports:
 *    - Missing shareId
 *    - Duplicate shareId groups
 *    - Missing createdAt field
 *    - Missing title field
 * - Fixes:
 *    - Missing shareId
 *    - Duplicate shareId (keeps oldest by createdAt; reassigns later ones)
 *
 * Ordering:
 * - Uses data.createdAt if present (Firestore Timestamp / ISO string / number)
 * - Otherwise falls back to Firestore metadata doc.createTime (reliable)
 *
 * shareId assignment:
 * - Assigns numeric string IDs: "1", "2", ...
 * - Respects already-used numeric shareIds
 *
 * Usage:
 *   node fix_share_ids.js --dry-run
 *   node fix_share_ids.js --apply
 *
 * Optional:
 *   node fix_share_ids.js --dry-run --collection=stories
 */

const admin = require("firebase-admin");
const fs = require("fs");

// Default collection; can override with --collection=NAME
let COLLECTION = "stories";

for (const a of process.argv.slice(2)) {
  if (a.startsWith("--collection=")) {
    COLLECTION = a.split("=", 2)[1] || COLLECTION;
  }
}

if (!fs.existsSync("./serviceAccountKey.json")) {
  console.error("Missing serviceAccountKey.json in this folder.");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require("./serviceAccountKey.json")),
});

const db = admin.firestore();

const args = process.argv.slice(2);
const APPLY = args.includes("--apply");
const DRY_RUN = args.includes("--dry-run") || !APPLY;

function hasField(obj, field) {
  return (
    obj &&
    Object.prototype.hasOwnProperty.call(obj, field) &&
    obj[field] !== null &&
    obj[field] !== ""
  );
}

function normalizeShareId(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s;
}

function getCreatedAtMillis(docData) {
  const ca = docData.createdAt;
  if (!ca) return Number.MAX_SAFE_INTEGER;
  // Firestore Timestamp has toMillis()
  if (typeof ca.toMillis === "function") return ca.toMillis();
  // If stored as epoch millis:
  if (typeof ca === "number") return ca;
  // If stored as ISO string:
  const t = Date.parse(ca);
  return Number.isNaN(t) ? Number.MAX_SAFE_INTEGER : t;
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY RUN" : "APPLY CHANGES"}`);
  console.log(`Collection: ${COLLECTION}`);

  const snap = await db.collection(COLLECTION).get();
  if (snap.empty) {
    console.log("No documents found. (Collection name might be wrong.)");
    return;
  }

  const docs = [];
  snap.forEach((d) => {
    const data = d.data();

    const createdAtFromField = getCreatedAtMillis(data);
    const createdAtMs =
      createdAtFromField !== Number.MAX_SAFE_INTEGER
        ? createdAtFromField
        : d.createTime
        ? d.createTime.toMillis()
        : Number.MAX_SAFE_INTEGER;

    docs.push({
      id: d.id,
      ref: d.ref,
      data,
      createdAtMs,
      shareId: normalizeShareId(data.shareId),

      // audit flags (field presence)
      missingCreatedAtField: !hasField(data, "createdAt"),
      missingTitle: !hasField(data, "title"),
    });
  });

  // Sort oldest first
  docs.sort((a, b) => a.createdAtMs - b.createdAtMs);

  // Map existing shareId -> doc IDs
  const shareIdToDocIds = new Map();
  for (const doc of docs) {
    if (!doc.shareId) continue;
    const arr = shareIdToDocIds.get(doc.shareId) || [];
    arr.push(doc.id);
    shareIdToDocIds.set(doc.shareId, arr);
  }

  // Find duplicate shareIds
  const duplicates = [];
  for (const [sid, ids] of shareIdToDocIds.entries()) {
    if (ids.length > 1) duplicates.push({ sid, ids });
  }

  // Track used numeric IDs
  const usedNumeric = new Set();
  for (const sid of shareIdToDocIds.keys()) {
    const n = Number(sid);
    if (Number.isInteger(n) && n > 0) usedNumeric.add(n);
  }

  function nextFreeNumeric() {
    let n = 1;
    while (usedNumeric.has(n)) n++;
    usedNumeric.add(n);
    return String(n);
  }

  // Docs needing shareId update: missing shareId OR duplicates (except oldest in group)
  const toUpdate = [];

  // Missing shareId
  for (const doc of docs) {
    if (!doc.shareId) toUpdate.push({ doc, reason: "missing" });
  }

  // Duplicates: keep first (oldest), reassign rest
  for (const dup of duplicates) {
    const dupDocs = docs.filter((d) => d.shareId === dup.sid);
    for (let i = 1; i < dupDocs.length; i++) {
      toUpdate.push({ doc: dupDocs[i], reason: `duplicate(${dup.sid})` });
    }
  }

  // Deduplicate update list by doc id
  const uniqueToUpdate = [];
  const seen = new Set();
  for (const item of toUpdate) {
    if (seen.has(item.doc.id)) continue;
    seen.add(item.doc.id);
    uniqueToUpdate.push(item);
  }

  // ---- Reporting ----
  console.log(`Total docs: ${docs.length}`);
  console.log(`Missing shareId: ${docs.filter((d) => !d.shareId).length}`);
  console.log(`Duplicate shareId groups: ${duplicates.length}`);
  console.log(`Docs to update (shareId): ${uniqueToUpdate.length}`);

  const missingCreatedAtDocs = docs.filter((d) => d.missingCreatedAtField);
  const missingTitleDocs = docs.filter((d) => d.missingTitle);

  console.log(`Missing createdAt field: ${missingCreatedAtDocs.length}`);
  console.log(`Missing title field: ${missingTitleDocs.length}`);

  if (missingCreatedAtDocs.length) {
    console.log("\nDocs missing createdAt field (first 50):");
    missingCreatedAtDocs.slice(0, 50).forEach((d) => {
      console.log(
        `- ${d.id} title=${JSON.stringify(d.data.title)} shareId=${d.shareId} createdAtMs=${d.createdAtMs}`
      );
    });
    if (missingCreatedAtDocs.length > 50) console.log("... (truncated)");
  }

  if (missingTitleDocs.length) {
    console.log("\nDocs missing title field (first 50):");
    missingTitleDocs.slice(0, 50).forEach((d) => {
      console.log(
        `- ${d.id} title=${JSON.stringify(d.data.title)} shareId=${d.shareId} createdAtMs=${d.createdAtMs}`
      );
    });
    if (missingTitleDocs.length > 50) console.log("... (truncated)");
  }

  // ---- Preview shareId updates ----
  if (!uniqueToUpdate.length) {
    console.log("\nNothing to update ✅");
    return;
  }

  const updates = uniqueToUpdate.map((item) => {
    const newShareId = nextFreeNumeric();
    return {
      ref: item.doc.ref,
      id: item.doc.id,
      oldShareId: item.doc.shareId,
      newShareId,
      reason: item.reason,
      createdAtMs: item.doc.createdAtMs,
      title: item.doc.data.title,
    };
  });

  console.log("\nPreview shareId updates (first 30):");
  for (const u of updates.slice(0, 30)) {
    console.log(
      `- doc=${u.id} title=${JSON.stringify(u.title)} createdAtMs=${u.createdAtMs} ` +
        `old=${u.oldShareId} -> new=${u.newShareId} reason=${u.reason}`
    );
  }

  if (DRY_RUN) {
    console.log("\nDRY RUN complete. Re-run with --apply to write changes.");
    return;
  }

  // ---- Apply updates ----
  const BATCH_SIZE = 400; // Firestore limit is 500 per batch
  let committed = 0;

  for (let i = 0; i < updates.length; i += BATCH_SIZE) {
    const chunk = updates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const u of chunk) {
      batch.update(u.ref, {
        shareId: u.newShareId,
        shareIdUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    committed += chunk.length;
    console.log(`Committed ${committed}/${updates.length}`);
  }

  console.log("✅ shareId updates applied successfully.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
