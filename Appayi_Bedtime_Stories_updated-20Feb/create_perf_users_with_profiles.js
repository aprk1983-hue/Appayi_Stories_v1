const admin = require("firebase-admin");
const fs = require("fs");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const auth = admin.auth();
const db = admin.firestore();

const COUNT = 1000;
const EMAIL_PREFIX = "perf_";
const EMAIL_DOMAIN = "example.com";
const PASSWORD = "PerfTest@12345";

function pad(n, width = 4) {
  return String(n).padStart(width, "0");
}

async function run() {
  console.log(`Creating ${COUNT} users + Firestore profiles...`);

  const created = [];
  let success = 0;
  let failed = 0;

  for (let i = 1; i <= COUNT; i++) {
    const email = `${EMAIL_PREFIX}${pad(i)}@${EMAIL_DOMAIN}`;

    try {
      const userRecord = await auth.createUser({
        email,
        password: PASSWORD,
        emailVerified: true,
        disabled: false,
      });

      const uid = userRecord.uid;

      // ✅ create matching Firestore profile doc
      await db.collection("users").doc(uid).set(
        {
          uid,
          provider: "password",
          isProfileComplete: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
          language: null,
          firstName: "Perf",
          lastName: `User${pad(i)}`,
        },
        { merge: true }
      );

      created.push({ email, password: PASSWORD, uid });
      success++;
      console.log(`✅ ${email} -> ${uid}`);
    } catch (e) {
      failed++;
      console.log(`❌ Failed ${email}: ${e.message}`);
    }
  }

  const csvLines = ["email,password,uid"];
  for (const u of created) csvLines.push(`${u.email},${u.password},${u.uid}`);
  fs.writeFileSync("users.csv", csvLines.join("\n"), "utf8");

  console.log(`\n✅ Done. Success: ${success}, Failed: ${failed}`);
  console.log(`📄 users.csv created`);
}

run().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
