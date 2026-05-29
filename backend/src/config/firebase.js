const admin = require("firebase-admin");

let messaging = null;
let firestore = null;

try {
  const hasFirebaseEnv =
    process.env.FIREBASE_PROJECT_ID &&
    process.env.FIREBASE_CLIENT_EMAIL &&
    process.env.FIREBASE_PRIVATE_KEY;

  if (hasFirebaseEnv && !admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
      }),
    });

    messaging = admin.messaging();
    firestore = admin.firestore();
    console.log("[firebase] Admin initialized from env");
  } else {
    console.log("[firebase] Admin disabled: env vars missing");
  }
} catch (error) {
  console.warn("[firebase] Admin init skipped:", error.message);
}

module.exports = {
  admin,
  messaging,
  firestore,
};