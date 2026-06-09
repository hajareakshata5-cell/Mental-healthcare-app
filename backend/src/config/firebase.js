const admin = require("firebase-admin");

let messaging = null;
let firestore = null;

try {
  let credential = null;

  if (process.env.FIREBASE_SERVICE_ACCOUNT_B64) {
    const serviceAccountJson = Buffer.from(
      process.env.FIREBASE_SERVICE_ACCOUNT_B64,
      "base64",
    ).toString("utf8");

    const serviceAccount = JSON.parse(serviceAccountJson);

    credential = admin.credential.cert(serviceAccount);

    console.log("[firebase] Admin using FIREBASE_SERVICE_ACCOUNT_B64", {
      projectId: serviceAccount.project_id,
      clientEmail: serviceAccount.client_email,
      hasPrivateKey: Boolean(serviceAccount.private_key),
    });
  } else {
    const hasFirebaseEnv =
      process.env.FIREBASE_PROJECT_ID &&
      process.env.FIREBASE_CLIENT_EMAIL &&
      process.env.FIREBASE_PRIVATE_KEY;

    if (hasFirebaseEnv) {
      credential = admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
      });

      console.log("[firebase] Admin using FIREBASE_PROJECT_ID fields", {
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        hasPrivateKey: Boolean(process.env.FIREBASE_PRIVATE_KEY),
      });
    }
  }

  if (credential && !admin.apps.length) {
    admin.initializeApp({ credential });
    messaging = admin.messaging();
    firestore = admin.firestore();
    console.log("[firebase] Admin initialized from env");
  } else if (!credential) {
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
