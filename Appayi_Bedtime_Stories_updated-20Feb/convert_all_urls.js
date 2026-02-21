const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// YOUR NEW DOMAIN
const NEW_DOMAIN = "https://media.thestoryhubs.com";

async function convertAllUrls() {
  console.log("Starting bulk conversion to " + NEW_DOMAIN + "...");
  const snapshot = await db.collection('stories').get();

  let count = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    let needsUpdate = false;
    let updates = {};

    // 1. Helper function to convert a single URL
    const convertUrl = (url) => {
      if (url && url.startsWith('gs://')) {
        // This regex replaces "gs://bucket-name/" with "https://media.thestoryhubs.com/"
        // It keeps the rest of the path (e.g. stories/en/...) exactly as is.
        return url.replace(/^gs:\/\/[^\/]+/, NEW_DOMAIN);
      }
      return url;
    };

    // 2. Check/Convert Root Audio URL
    const newAudioUrl = convertUrl(data.audioUrl);
    if (newAudioUrl !== data.audioUrl) {
      console.log(`[${data.title}] Updating root audioUrl...`);
      updates.audioUrl = newAudioUrl;
      needsUpdate = true;
    }

    // 3. Check/Convert Root Cover Image
    const newCoverUrl = convertUrl(data.coverImageUrl);
    if (newCoverUrl !== data.coverImageUrl) {
      updates.coverImageUrl = newCoverUrl;
      needsUpdate = true;
    }

    // 4. Check/Convert Audio Script Array
    if (Array.isArray(data.audioScript)) {
      let scriptModified = false;
      const newScript = data.audioScript.map(item => {
        if (item.type === 'audio' && item.audioUrl && item.audioUrl.startsWith('gs://')) {
          scriptModified = true;
          return { ...item, audioUrl: convertUrl(item.audioUrl) };
        }
        return item;
      });

      if (scriptModified) {
        console.log(`[${data.title}] Updating audioScript URLs...`);
        updates.audioScript = newScript;
        needsUpdate = true;
      }
    }

    // 5. Commit updates if anything changed
    if (needsUpdate) {
      await db.collection('stories').doc(doc.id).update(updates);
      count++;
    }
  }

  console.log(`\nDONE! Successfully updated ${count} stories.`);
}

convertAllUrls();