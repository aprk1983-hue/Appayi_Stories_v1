// functions/src/index.ts
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

initializeApp();

const BUCKET = "my-audio-story-app.firebasestorage.app";
const REGION = "us-central1";
const TOPIC_NEW_STORIES = "new_stories";

/** "goodnight-moonberry-forest-001" -> "Goodnight Moonberry Forest 001" */
function titleFromSlug(s: string): string {
  return s.replace(/[-_]+/g, " ")
    .split(" ").filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

/** Build gs:// URL */
function gsUrl(name: string): string { return `gs://${BUCKET}/${name}`; }

/** Expect: stories/<lang>/<category>/<slug>/<file> */
function parseStoriesPath(name: string) {
  const p = name.split("/").filter(Boolean);
  if (p.length < 5) return null;
  if (p[0].toLowerCase() !== "stories") return null;
  const lang = (p[1] || "").toLowerCase();
  const category = p[2] || "";
  const slug = p[3] || "";
  const file = p.slice(4).join("/");
  if (!lang || !category || !slug || !file) return null;
  return { lang, category, slug, file };
}

/** Determine whether a story doc has playable audio. Supports both Cloudflare audioUrl and storage-ingested audioScript. */
function extractPlayableAudioUrl(data: any): string | null {
  if (!data || typeof data !== "object") return null;

  // Cloudflare style (manual story creation)
  if (typeof data.audioUrl === "string" && data.audioUrl.trim().length > 0) {
    return data.audioUrl.trim();
  }

  // Storage ingestion style
  const script = (data as any).audioScript;
  if (Array.isArray(script)) {
    for (const item of script) {
      const t = String(item?.type || "").toLowerCase();
      const url = typeof item?.audioUrl === "string" ? item.audioUrl.trim() : "";
      if ((t === "audio" || t === "mp3" || t === "narration") && url) return url;
    }
  }

  return null;
}

async function sendNewStoryNotification(storyId: string, title: string) {
  try {
    await getMessaging().send({
      topic: TOPIC_NEW_STORIES,
      notification: {
        title: "New bedtime story added 🌙",
        body: `${title} is now available.`,
      },
      data: {
        storyId,
        route: "whats_new",
      },
    });
    logger.info("✅ Sent new story notification", { storyId, title });
  } catch (e) {
    // Never break ingestion or story creation if messaging fails
    logger.warn("⚠️ Failed to send notification", { storyId, err: String(e) });
  }
}

/**
 * STORAGE INGEST (unchanged):
 * Uploading files to: stories/<lang>/<category>/<slug>/<file>
 * - image/* -> coverImageUrl
 * - audio/* -> audioScript
 */
export const ingestStoryOnUpload = onObjectFinalized(
  { bucket: BUCKET, region: REGION },
  async evt => {
    const obj = evt.data;
    const name = obj.name || "";
    if (!name) { logger.warn("No object name; skip."); return; }

    const info = parseStoriesPath(name);
    if (!info) {
      logger.debug("Upload not in stories path; skipping.", { name });
      return;
    }

    // Ignore folder placeholder events
    const ct = (obj.contentType || "").trim();
    if (!ct) { logger.debug("Empty contentType; likely folder.", { name }); return; }

    const db = getFirestore();
    const ref = db.collection("stories").doc(info.slug);
    const snap = await ref.get();

    const base: any = {
      title: titleFromSlug(info.slug),
      language: info.lang.toUpperCase(),
      category: info.category,
      isPremium: false,
      likes: 0,
      dislikes: 0,
      views: 0,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!snap.exists) base.createdAt = FieldValue.serverTimestamp();

    if (ct.startsWith("image/")) {
      await ref.set(
        { ...base, coverImageUrl: gsUrl(name) },
        { merge: true }
      );
      logger.info("Cover saved", { slug: info.slug, file: info.file });
      return;
    }

    if (ct.startsWith("audio/")) {
      // Track whether this story already had playable audio BEFORE we write audioScript
      const hadAudioBefore = snap.exists && !!extractPlayableAudioUrl(snap.data());

      await ref.set(
        { ...base, audioScript: [{ type: "audio", audioUrl: gsUrl(name) }] },
        { merge: true }
      );
      logger.info("Audio saved", { slug: info.slug, file: info.file });

      // Notify only the first time audio becomes available and only if not already notified
      if (!hadAudioBefore) {
        const afterSnap = await ref.get();
        const after = afterSnap.data() || {};
        if (!after.notifiedNewStoryAt) {
          await sendNewStoryNotification(info.slug, String(after.title || titleFromSlug(info.slug)));
          await ref.set({ notifiedNewStoryAt: FieldValue.serverTimestamp() }, { merge: true });
        }
      }
      return;
    }

    logger.debug("Unsupported content type; ignoring.", { ct });
  }
);

/**
 * FIRESTORE TRIGGERS (NEW):
 * These make notifications work when you manually add stories in Firestore with Cloudflare `audioUrl`,
 * and also when audio becomes available later.
 *
 * Collection: stories/{storyId}
 */

// If a new story is created and already has playable audio, notify once.
export const notifyNewStoryWhenCreated = onDocumentCreated(
  { document: "stories/{storyId}", region: REGION },
  async (event) => {
    const storyId = event.params.storyId as string;
    const data = event.data?.data();

    if (!data) return;
    if (data.notifiedNewStoryAt) return;

    const playable = extractPlayableAudioUrl(data);
    if (!playable) return;

    const title = (data.title && String(data.title).trim()) || titleFromSlug(storyId);
    await sendNewStoryNotification(storyId, title);

    // Mark as notified to avoid duplicates
    try {
      await getFirestore().collection("stories").doc(storyId).set(
        { notifiedNewStoryAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    } catch (e) {
      logger.warn("Failed to set notifiedNewStoryAt on create", { storyId, err: String(e) });
    }
  }
);

// If a story is updated from not-playable -> playable, notify once.
export const notifyNewStoryWhenPlayableAdded = onDocumentUpdated(
  { document: "stories/{storyId}", region: REGION },
  async (event) => {
    const storyId = event.params.storyId as string;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!after) return;
    if (after.notifiedNewStoryAt) return;

    const beforePlayable = !!extractPlayableAudioUrl(before);
    const afterPlayable = !!extractPlayableAudioUrl(after);

    if (beforePlayable || !afterPlayable) return;

    const title = (after.title && String(after.title).trim()) || titleFromSlug(storyId);
    await sendNewStoryNotification(storyId, title);

    try {
      await getFirestore().collection("stories").doc(storyId).set(
        { notifiedNewStoryAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    } catch (e) {
      logger.warn("Failed to set notifiedNewStoryAt on update", { storyId, err: String(e) });
    }
  }
);
