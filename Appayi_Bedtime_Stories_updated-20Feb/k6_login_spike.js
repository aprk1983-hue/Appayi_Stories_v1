import http from "k6/http";
import { check, sleep } from "k6";
import { SharedArray } from "k6/data";

export const options = {
  scenarios: {
    login_spike: {
      executor: "per-vu-iterations",
      vus: 1000,              // 100 users at same time
      iterations: 1,         // each user does the flow once
      maxDuration: "5m",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],            // <1% errors
    http_req_duration: ["p(95)<1500"],         // overall p95 < 1.5s (tune later)
  },
};

const API_KEY = "AIzaSyCYmTKuhpareST4SyYGTSkYu_j_MJvCy80";
const PROJECT_ID = "my-audio-story-app";

// ✅ Adjust these to match your Firestore structure (common defaults shown)
const STORIES_COLLECTION = "stories";          // your stories collection
const USERS_COLLECTION = "users";              // if you have user profiles like users/{uid}

// Read users from CSV: email,password,uid
const users = new SharedArray("users", function () {
  const csv = open("./users.csv").trim().split("\n");
  const rows = csv.slice(1); // skip header
  return rows.map((line) => {
    const [email, password] = line.split(",");
    return { email, password };
  });
});

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
    timeout: "20s",
  });

  check(res, {
    "login status is 200": (r) => r.status === 200,
  });

  if (res.status !== 200) return null;

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
    timeout: "20s",
  });

  check(res, {
    [`${tagName} status 200/404`]: (r) => r.status === 200 || r.status === 404,
  });

  return res;
}

function firestoreListCollection(idToken, collectionName, pageSize, tagName) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionName}?pageSize=${pageSize}`;

  const res = http.get(url, {
    headers: { Authorization: `Bearer ${idToken}` },
    tags: { name: tagName },
    timeout: "20s",
  });

  check(res, {
    [`${tagName} status 200`]: (r) => r.status === 200,
  });

  return res;
}

export default function () {
  const u = users[__VU - 1]; // 1 user per VU
  const auth = signIn(u.email, u.password);

  if (!auth) return;

  const { idToken, localId } = auth;

  // Post-login warm calls (edit to match your app usage)
  // 1) user profile doc (if exists)
  firestoreGetDoc(idToken, `${USERS_COLLECTION}/${localId}`, "FS_user_profile");

  // 2) list stories (first page)
  const storiesRes = firestoreListCollection(idToken, STORIES_COLLECTION, 20, "FS_stories_list");

  // 3) get one story doc (first from list, if available)
  try {
    const j = storiesRes.json();
    if (j && j.documents && j.documents.length > 0) {
      const fullName = j.documents[0].name; // full resource name
      const parts = fullName.split("/documents/");
      if (parts.length === 2) {
        const docPath = parts[1];
        firestoreGetDoc(idToken, docPath, "FS_story_doc");
      }
    }
  } catch (e) {
    // ignore parse issues
  }

  sleep(1);
}
