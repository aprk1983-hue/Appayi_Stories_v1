/**
 * Backfill missing fields for stories:
 * - If createdAt is missing: set createdAt = document createTime (best available historic timestamp)
 * - Always set updatedAt = serverTimestamp()
 * - If title is missing:
 *    - If slug exists: derive title from slug by removing trailing language suffix like "-ta"
 *    - Else: use doc id similarly
 *
 * Usage:
 *   node backfill_missing_fields.js --dry-run --collection=stories
 *   node backfill_missing_fields.js --apply   --collection=stories
 *
 * Requires:
 *   - serviceAccountKey.json in the same folder
 *   - firebase-admin installed
 */

const admin = require("firebase-admin");
const fs = require("fs");

// Defaults; override with --collection=NAME
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

function deriveTitleFromSlugOrId(slugOrId) {
  if (!slugOrId) return null;
  let s = String(slugOrId).trim();
  if (!s) return null;

  // Remove trailing language code suffix like "-ta", "-en", "-hi", etc.
  // Only if it matches "-xx" at the end where xx are letters.
  s = s.replace(/-[a-zA-Z]{2,3}$/, "");

  return s.trim() || null;
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY RUN" : "APPLY CHANGES"}`);
  console.log(`Collection: ${COLLECTION}`);

  const snap = await db.collection(COLLECTION).get();
  if (snap.empty) {
    console.log("No documents found. (Collection name might be wrong.)");
    return;
  }

  const candidates = [];

  snap.forEach((d) => {
    const data = d.data() || {};

    const missingCreatedAt = !hasField(data, "createdAt");
    const missingTitle = !hasField(data, "title");

    if (!missingCreatedAt && !missingTitle) return;

    const slug = data.slug;
    const derivedTitle = missingTitle
      ? deriveTitleFromSlugOrId(slug) || deriveTitleFromSlugOrId(d.id)
      : null;

    const createdAtFromCreateTime = d.createTime ? d.createTime.toDate() : null;

    candidates.push({
      id: d.id,
      ref: d.ref,
      missingCreatedAt,
      missingTitle,
      derivedTitle,
      createdAtFromCreateTime,
      slug,
    });
  });

  console.log(`Total docs: ${snap.size}`);
  console.log(`Docs missing createdAt and/or title: ${candidates.length}`);

  if (!candidates.length) {
    console.log("Nothing to backfill ✅");
    return;
  }

  console.log("\nPreview (first 50):");
  for (const c of candidates.slice(0, 50)) {
    console.log(
      `- ${c.id} | missingCreatedAt=${c.missingCreatedAt} missingTitle=${c.missingTitle} ` +
        `slug=${JSON.stringify(c.slug)} derivedTitle=${JSON.stringify(c.derivedTitle)} createTime=${c.createdAtFromCreateTime}`
    );
  }
  if (candidates.length > 50) console.log("... (truncated)");

  if (DRY_RUN) {
    console.log("\nDRY RUN complete. Re-run with --apply to write changes.");
    return;
  }

  const BATCH_SIZE = 400;
  let committed = 0;

  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const chunk = candidates.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const c of chunk) {
      const updates = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (c.missingCreatedAt) {
        // Store as Firestore Timestamp
        if (c.createdAtFromCreateTime) {
          updates.createdAt = admin.firestore.Timestamp.fromDate(c.createdAtFromCreateTime);
        } else {
          updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
        }
      }

      if (c.missingTitle) {
        if (c.derivedTitle) {
          updates.title = c.derivedTitle;
        }
      }

      batch.update(c.ref, updates);
    }

    await batch.commit();
    committed += chunk.length;
    console.log(`Committed ${committed}/${candidates.length}`);
  }

  console.log("✅ Backfill applied successfully.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
