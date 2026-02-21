// functions/src/index.ts
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {logger} from "firebase-functions";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

initializeApp();

const BUCKET = "my-audio-story-app.firebasestorage.app";
const REGION = "us-central1";

/** "goodnight-moonberry-forest-001" -> "Goodnight Moonberry Forest 001" */
function titleFromSlug(s:string):string {
  return s.replace(/[-_]+/g," ")
    .split(" ").filter(Boolean)
    .map(w=>w.charAt(0).toUpperCase()+w.slice(1)).join(" ");
}

/** Build gs:// URL */
function gsUrl(name:string):string { return `gs://${BUCKET}/${name}`; }

/** Expect: stories/<lang>/<category>/<slug>/<file> */
function parseStoriesPath(name:string){
  const p = name.split("/").filter(Boolean);
  if (p.length < 5) return null;
  if (p[0].toLowerCase() !== "stories") return null;
  const lang = (p[1]||"").toLowerCase();
  const category = p[2]||"";
  const slug = p[3]||"";
  const file = p.slice(4).join("/");
  if (!lang || !category || !slug || !file) return null;
  return {lang,category,slug,file};
}

export const ingestStoryOnUpload = onObjectFinalized(
  {bucket:BUCKET,region:REGION},
  async evt=>{
    const obj = evt.data;
    const name = obj.name || "";
    if (!name) { logger.warn("No object name; skip."); return; }

    const info = parseStoriesPath(name);
    if (!info) {
      logger.debug("Upload not in stories path; skipping.", {name});
      return;
    }

    // Ignore folder placeholder events
    const ct = (obj.contentType || "").trim();
    if (!ct) { logger.debug("Empty contentType; likely folder.", {name}); return; }

    const db = getFirestore();
    const ref = db.collection("stories").doc(info.slug);
    const snap = await ref.get();

    const base:any = {
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
        {...base,coverImageUrl:gsUrl(name)},
        {merge:true}
      );
      logger.info("Cover saved",{slug:info.slug,file:info.file});
      return;
    }

    if (ct.startsWith("audio/")) {
      await ref.set(
        {...base,audioScript:[{type:"audio",audioUrl:gsUrl(name)}]},
        {merge:true}
      );
      logger.info("Audio saved",{slug:info.slug,file:info.file});
      return;
    }

    logger.debug("Unsupported content type; ignoring.",{ct});
  }
);
