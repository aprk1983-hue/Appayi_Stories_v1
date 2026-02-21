/**
 * Bulk delete test users from Firebase Auth + matching Firestore user docs.
 *
 * Default mode is DRY RUN (no deletes). To actually delete, run with: --delete
 *
 * Usage:
 *   node delete_perf_users.js                 # dry run (prints what it WOULD delete)
 *   node delete_perf_users.js --delete        # actually deletes
 *
 * Optional overrides:
 *   --prefix perf_        (default: perf_)
 *   --domain example.com  (default: example.com)
 *
 * Requirements:
 *   - npm i firebase-admin
 *   - serviceAccountKey.json in same folder (Firebase Admin SDK service account key)
 */

const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

const args = process.argv.slice(2);
const DRY_RUN = !args.includes("--delete");

function getArgValue(flag, fallback) {
  const idx = args.indexOf(flag);
  if (idx !== -1 && args[idx + 1]) return args[idx + 1];
  return fallback;
}

const EMAIL_PREFIX = getArgValue("--prefix", "perf_");
const EMAIL_DOMAIN = getArgValue("--domain", "example.com");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const auth = admin.auth();
const db = admin.firestore();

async function run() {
  console.log("Deleting perf users from Firebase Auth + Firestore users collection...");
  console.log(`Mode: ${DRY_RUN ? "DRY RUN (no deletes)" : "DELETE (will remove users)"}`);
  console.log(`Match: email startsWith("${EMAIL_PREFIX}") AND endsWith("@${EMAIL_DOMAIN}")`);

  let matched = 0;
  let deletedAuth = 0;
  let deletedFs = 0;
  let pageToken;

  do {
    const list = await auth.listUsers(1000, pageToken);
    pageToken = list.pageToken;

    for (const user of list.users) {
      const email = user.email || "";
      if (email.startsWith(EMAIL_PREFIX) && email.endsWith(`@${EMAIL_DOMAIN}`)) {
        matched++;

        if (DRY_RUN) {
          console.log(`[DRY] Would delete Auth user: uid=${user.uid}, email=${email}`);
          console.log(`[DRY] Would delete Firestore doc: users/${user.uid}`);
          continue;
        }

        // delete firestore users/{uid} doc (ignore if missing)
        try {
          await db.collection("users").doc(user.uid).delete();
          deletedFs++;
        } catch (_) {}

        // delete auth user
        await auth.deleteUser(user.uid);
        deletedAuth++;

        if (deletedAuth % 20 === 0) {
          console.log(`🗑️ Deleted ${deletedAuth} auth users...`);
        }
      }
    }
  } while (pageToken);

  if (DRY_RUN) {
    console.log(`✅ Done (dry run). Matched users: ${matched}`);
  } else {
    console.log(`✅ Done. Deleted Auth users: ${deletedAuth}, Firestore docs: ${deletedFs}`);
  }
}

run().catch((e) => {
  console.error("❌ Failed:", e);
  process.exit(1);
});
