import http from "k6/http";
import { check, sleep } from "k6";
import { SharedArray } from "k6/data";

// --------------------
// Config (override via -e)
// --------------------
const API_KEY = __ENV.API_KEY || "AIzaSyCYmTKuhpareST4SyYGTSkYu_j_MJvCy80";
const PROJECT_ID = __ENV.PROJECT_ID || "my-audio-story-app";
const USERS_CSV = __ENV.USERS_CSV || "./users.csv";

// Concurrency + duration
const VUS = Number(__ENV.VUS || 200);
const DURATION = __ENV.DURATION || "10m";

// Think time (seconds)
const THINK_MIN = Number(__ENV.THINK_MIN || 1.0);
const THINK_MAX = Number(__ENV.THINK_MAX || 3.0);

// Home feed limits
const PAGE_SIZE = Number(__ENV.PAGE_SIZE || 20);

// Languages (comma-separated)
const LANGS = (__ENV.LANGS || "en,hi,ta")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

// Toggle extra reads
const READ_PROFILE_EACH_LOOP = (__ENV.READ_PROFILE_EACH_LOOP || "true") === "true";

// --------------------
// k6 options
// --------------------
export const options = {
  scenarios: {
    browse_soak: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
      gracefulStop: "30s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<2500"], // soak is usually looser than spike; tune as needed
  },
};

// --------------------
// Load users
// users.csv format expected: email,password,uid
// --------------------
const users = new SharedArray("users", function () {
  const csv = open(USERS_CSV).trim().split("\n");
  const rows = csv.slice(1); // skip header
  return rows.map((line) => {
    const parts = line.split(",");
    return {
      email: (parts[0] || "").trim(),
      password: (parts[1] || "").trim(),
      uid: (parts[2] || "").trim(),
    };
  });
});

// --------------------
// Helpers
// --------------------
function randBetween(min, max) {
  return min + Math.random() * (max - min);
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function signIn(email, password) {
  const url =
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;

  const payload = JSON.stringify({
    email,
    password,
    returnSecureToken: true,
  });

  const res = http.post(url, payload, {
    headers: { "Content-Type": "application/json" },
    tags: { name: "AUTH_signInWithPassword" },
    timeout: "25s",
  });

  const ok = check(res, { "login status is 200": (r) => r.status === 200 });
  if (!ok) return null;

  const body = res.json();
  return {
    idToken: body.idToken,
    localId: body.localId, // uid
  };
}

function firestoreGetDoc(idToken, docPath, tagName) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}`;

  const res = http.get(url, {
    headers: { Authorization: `Bearer ${idToken}` },
    tags: { name: tagName },
    timeout: "25s",
  });

  check(res, {
    [`${tagName} status 200/404`]: (r) => r.status === 200 || r.status === 404,
  });

  return res;
}

// Firestore structured query (runQuery)
function firestoreRunQuery(idToken, structuredQuery, tagName) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`;

  const payload = JSON.stringify({ structuredQuery });

  const res = http.post(url, payload, {
    headers: {
      Authorization: `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    tags: { name: tagName },
    timeout: "25s",
  });

  check(res, {
    [`${tagName} status 200`]: (r) => r.status === 200,
  });

  return res;
}

function extractDocPathsFromRunQuery(res) {
  // runQuery returns JSON lines (array of objects). k6 res.json() parses as array if JSON is valid.
  // In practice, it’s a JSON array for REST response; we handle both safely.
  try {
    const data = res.json();
    if (!Array.isArray(data)) return [];

    const paths = [];
    for (const item of data) {
      // item.document.name looks like:
      // projects/{project}/databases/(default)/documents/stories/{docId}
      const name = item?.document?.name;
      if (typeof name === "string" && name.includes("/documents/")) {
        const docPath = name.split("/documents/")[1];
        if (docPath) paths.push(docPath);
      }
    }
    return paths;
  } catch (e) {
    return [];
  }
}

// Build a stories query by language + orderBy field
function storiesQueryByLanguage(lang, orderField, direction = "DESCENDING", limit = PAGE_SIZE) {
  return {
    from: [{ collectionId: "stories" }],
    where: {
      fieldFilter: {
        field: { fieldPath: "language" },
        op: "EQUAL",
        value: { stringValue: lang },
      },
    },
    orderBy: [{ field: { fieldPath: orderField }, direction }],
    limit,
  };
}

// --------------------
// Per-VU state
// --------------------
let session = null; // { idToken, uid }
let chosenLang = null;

export default function () {
  // Ensure we have enough test users
  const u = users[__VU - 1];
  if (!u || !u.email) {
    // Not enough rows in users.csv for current VU count
    return;
  }

  // Login once per VU
  if (!session) {
    const auth = signIn(u.email, u.password);
    if (!auth) return;

    session = { idToken: auth.idToken, uid: auth.localId };
    chosenLang = pick(LANGS);
  }

  const { idToken, uid } = session;

  // Optional: simulate app reading profile periodically
  if (READ_PROFILE_EACH_LOOP) {
    firestoreGetDoc(idToken, `users/${uid}`, "FS_user_profile");
  }

  // Simulate “Home browsing”
  // 1) What's New (createdAt desc)
  const qNew = storiesQueryByLanguage(chosenLang, "createdAt", "DESCENDING", PAGE_SIZE);
  const resNew = firestoreRunQuery(idToken, qNew, "FS_stories_whats_new");
  const newDocs = extractDocPathsFromRunQuery(resNew);

  sleep(randBetween(THINK_MIN, THINK_MAX));

  // 2) Popular (likes desc)
  const qLikes = storiesQueryByLanguage(chosenLang, "likes", "DESCENDING", PAGE_SIZE);
  const resLikes = firestoreRunQuery(idToken, qLikes, "FS_stories_popular");
  const likeDocs = extractDocPathsFromRunQuery(resLikes);

  sleep(randBetween(THINK_MIN, THINK_MAX));

  // 3) Most Viewed (views desc)
  const qViews = storiesQueryByLanguage(chosenLang, "views", "DESCENDING", PAGE_SIZE);
  const resViews = firestoreRunQuery(idToken, qViews, "FS_stories_most_viewed");
  const viewDocs = extractDocPathsFromRunQuery(resViews);

  // Open one story doc (tap a tile)
  const combined = [...newDocs, ...likeDocs, ...viewDocs];
  if (combined.length > 0) {
    const docPath = pick(combined);
    firestoreGetDoc(idToken, docPath, "FS_story_doc_open");
  }

  // Think time before next browse loop
  sleep(randBetween(THINK_MIN, THINK_MAX));
}
