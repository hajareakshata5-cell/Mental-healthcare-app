const dotenv = require("dotenv");

dotenv.config();

const required = ["MONGODB_URI", "JWT_SECRET"];

required.forEach((key) => {
  if (!process.env[key]) {
    // eslint-disable-next-line no-console
    console.warn(`[env] Missing required environment variable: ${key}`);
  }
});

module.exports = {
  env: process.env.NODE_ENV || "development",
  port: Number(process.env.PORT || 3000),
  mongodbUri: process.env.MONGODB_URI,
  jwtSecret: process.env.JWT_SECRET || "change_me_in_production",
  jwtExpire: process.env.JWT_EXPIRE || "15m",
  jwtRefreshSecret:
    process.env.JWT_REFRESH_SECRET ||
    process.env.JWT_SECRET ||
    "change_me_in_production",
  jwtRefreshExpire: process.env.JWT_REFRESH_EXPIRE || "30d",
  razorpayKeyId: process.env.RAZORPAY_KEY_ID,
  razorpayKeySecret: process.env.RAZORPAY_KEY_SECRET,
  razorpayWebhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET,
  webhookReplayWindowSec: Number(process.env.WEBHOOK_REPLAY_WINDOW_SEC || 900),
  webhookMaxAgeSec: Number(process.env.WEBHOOK_MAX_AGE_SEC || 3600),
  trustedProxy: process.env.TRUST_PROXY || "loopback",
  stunServers: (
    process.env.WEBRTC_STUN_SERVERS ||
    "stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302"
  )
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
  turnServers: (process.env.WEBRTC_TURN_SERVERS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
  corsOrigins: (
    process.env.CORS_ORIGIN ||
    "https://mentalhealthapp-ba7bb.web.app,http://localhost:5173,http://localhost:3000"
  )
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
  socketCorsOrigins: (
    process.env.SOCKET_IO_CORS_ORIGIN ||
    "https://mentalhealthapp-ba7bb.web.app,http://localhost:5173,http://localhost:3000"
  )
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID,
  firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  firebasePrivateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n"),
};
