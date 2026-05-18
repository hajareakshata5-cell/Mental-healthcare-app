const admin = require("firebase-admin");
const env = require("../config/env");
const ApiError = require("../utils/ApiError");

let firebaseApp;

function getFirebaseApp() {
  if (firebaseApp) {
    return firebaseApp;
  }

  if (
    !env.firebaseProjectId ||
    !env.firebaseClientEmail ||
    !env.firebasePrivateKey
  ) {
    throw new ApiError(
      500,
      "Firebase Admin is not configured. Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY.",
    );
  }

  firebaseApp = admin.initializeApp({
    credential: admin.credential.cert({
      projectId: env.firebaseProjectId,
      clientEmail: env.firebaseClientEmail,
      privateKey: env.firebasePrivateKey,
    }),
  });

  return firebaseApp;
}

async function verifyFirebaseIdToken(idToken) {
  const app = getFirebaseApp();
  return admin.auth(app).verifyIdToken(idToken);
}

module.exports = { getFirebaseApp, verifyFirebaseIdToken };
