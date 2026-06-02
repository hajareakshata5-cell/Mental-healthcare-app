const bcrypt = require("bcryptjs");
const User = require("../models/User");
const Subscription = require("../models/Subscription");
const ApiError = require("../utils/ApiError");
const asyncHandler = require("../utils/asyncHandler");
const { verifyFirebaseIdToken } = require("../services/firebaseAdmin");
const {
  issueAuthTokens,
  verifyRefreshToken,
} = require("../services/tokenService");

const { sendVerificationOtpEmail } = require("../services/emailService");

function normalizeEmail(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}

function randomAlias() {
  return `anon_${Math.random().toString(36).slice(2, 10)}`;
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function setAndSendEmailOtp(user) {
  const otp = generateOtp();
  user.emailVerificationOtpHash = await bcrypt.hash(otp, 10);
  user.emailVerificationOtpExpiresAt = new Date(Date.now() + 10 * 60 * 1000);
  user.emailVerificationOtpLastSentAt = new Date();
  await user.save();

  await sendVerificationOtpEmail({
    to: user.email,
    otp,
    username: user.displayName || user.username,
  });
}

async function ensureUniqueUsername(baseUsername) {
  let username = baseUsername;
  let attempts = 0;

  while (await User.findOne({ username })) {
    attempts += 1;
    username = `${baseUsername}_${Math.random().toString(36).slice(2, 6)}`;

    if (attempts > 5) {
      username = `user_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
      break;
    }
  }

  return username;
}

function buildAuthResponse(user, tokens) {
  return {
    success: true,
    token: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    user: {
      id: user._id,
      email: user.email,
      username: user.username,
      alias: user.anonymousAlias,
      authProvider: user.authProvider,
      freeCallsRemaining: user.freeCallsRemaining ?? 2,
      isSubscribed: user.isSubscribed ?? false,
      healing: user.healing || {
        wellnessXp: 0,
        healingLevel: 1,
        meditationStreak: 0,
        moodStreak: 0,
        hydrationStreak: 0,
        achievements: [],
      },
    },
  };
}

const register = asyncHandler(async (req, res) => {
  const { email, password, username, displayName } = req.body;

  if (!email || !password || !username) {
    throw new ApiError(400, "email, password and username are required");
  }

  const normalizedEmail = normalizeEmail(email);
  const cleanUsername = String(username).trim();

  if (cleanUsername.length < 3) {
    throw new ApiError(400, "username must be at least 3 characters");
  }

  const existing = await User.findOne({ email: normalizedEmail });

  if (existing && existing.emailVerified) {
    throw new ApiError(
      409,
      "This email is already registered. Please sign in.",
    );
  }

  if (existing && !existing.emailVerified) {
    existing.username = cleanUsername;
    existing.displayName = displayName || cleanUsername;
    existing.passwordHash = await bcrypt.hash(password, 12);
    existing.authProvider = "email";
    if (!existing.anonymousAlias) {
      existing.anonymousAlias = randomAlias();
    }

      try {
    await setAndSendEmailOtp(existing);
  } catch (error) {
    console.error("OTP_EMAIL_SEND_FAILED_EXISTING_USER", {
      message: error.message,
      code: error.code,
      command: error.command,
      response: error.response,
    });

    throw new ApiError(
      500,
      "Verification email could not be sent. Please try again.",
    );
  }
    return res.status(200).json({
      success: true,
      requiresVerification: true,
      email: existing.email,
      message: "Verification OTP sent to your email",
    });
  }

  const passwordHash = await bcrypt.hash(password, 12);

  const user = await User.create({
    email: normalizedEmail,
    username: cleanUsername,
    displayName: displayName || cleanUsername,
    passwordHash,
    authProvider: "email",
    anonymousAlias: randomAlias(),
    emailVerified: false,
  });

  await Subscription.create({
    userId: user._id,
    plan: "free",
    status: "free",
    benefits: ["2 free anonymous calls"],
  });

    try {
    await setAndSendEmailOtp(user);
  } catch (error) {
    console.error("OTP_EMAIL_SEND_FAILED_NEW_USER", {
      message: error.message,
      code: error.code,
      command: error.command,
      response: error.response,
    });

    await User.findByIdAndDelete(user._id);
    await Subscription.deleteOne({ userId: user._id });
    throw new ApiError(
      500,
      "Account creation failed because verification email could not be sent",
    );
  }

  res.status(201).json({
    success: true,
    requiresVerification: true,
    email: user.email,
    message: "Verification OTP sent to your email",
  });
});
const login = asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    throw new ApiError(400, "email and password are required");
  }

  const normalizedEmail = normalizeEmail(email);

  const user = await User.findOne({ email: normalizedEmail });
  if (!user || !user.passwordHash) {
    throw new ApiError(401, "Invalid credentials");
  }

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    throw new ApiError(401, "Invalid credentials");
  }

  if (!user.emailVerified) {
    throw new ApiError(403, "Please verify your email before signing in");
  }

  user.lastAuthAt = new Date();
  await user.save();
  const tokens = issueAuthTokens(user);

  res.json(buildAuthResponse(user, tokens));
});

const verifyOtp = asyncHandler(async (req, res) => {
  const { email, otp } = req.body;

  if (!email || !otp) {
    throw new ApiError(400, "email and otp are required");
  }

  const normalizedEmail = normalizeEmail(email);
  const user = await User.findOne({ email: normalizedEmail });

  if (!user || !user.passwordHash) {
    throw new ApiError(404, "User not found");
  }

  if (user.emailVerified) {
    return res.json({
      success: true,
      verified: true,
      message: "Email is already verified. Please sign in.",
    });
  }

  if (
    !user.emailVerificationOtpHash ||
    !user.emailVerificationOtpExpiresAt ||
    user.emailVerificationOtpExpiresAt < new Date()
  ) {
    throw new ApiError(400, "OTP expired. Please request a new OTP.");
  }

  const validOtp = await bcrypt.compare(
    String(otp).trim(),
    user.emailVerificationOtpHash,
  );

  if (!validOtp) {
    throw new ApiError(400, "Invalid OTP");
  }

  user.emailVerified = true;
  user.emailVerificationOtpHash = null;
  user.emailVerificationOtpExpiresAt = null;
  user.emailVerificationOtpLastSentAt = null;
  await user.save();

  res.json({
    success: true,
    verified: true,
    message: "Email verified successfully. Please sign in.",
  });
});

const resendOtp = asyncHandler(async (req, res) => {
  const { email } = req.body;

  if (!email) {
    throw new ApiError(400, "email is required");
  }

  const normalizedEmail = normalizeEmail(email);
  const user = await User.findOne({ email: normalizedEmail });

  if (!user || !user.passwordHash) {
    throw new ApiError(404, "User not found");
  }

  if (user.emailVerified) {
    return res.json({
      success: true,
      verified: true,
      message: "Email is already verified. Please sign in.",
    });
  }

  const lastSent = user.emailVerificationOtpLastSentAt;
  if (lastSent && Date.now() - lastSent.getTime() < 60 * 1000) {
    throw new ApiError(429, "Please wait before requesting another OTP");
  }

  await setAndSendEmailOtp(user);

  res.json({
    success: true,
    requiresVerification: true,
    email: user.email,
    message: "Verification OTP sent again",
  });
});

const debugSendOtpEmail = asyncHandler(async (req, res) => {
  const { email } = req.body;

  if (!email) {
    throw new ApiError(400, "email is required");
  }

  try {
    await sendVerificationOtpEmail({
      to: normalizeEmail(email),
      otp: "123456",
      username: "Debug User",
    });

    res.json({
      success: true,
      message: "Debug email sent successfully",
      smtp: {
        host: process.env.SMTP_HOST ? "YES" : "NO",
        port: process.env.SMTP_PORT || null,
        user: process.env.SMTP_USER ? "YES" : "NO",
        pass: process.env.SMTP_PASS ? "YES" : "NO",
        from: process.env.SMTP_FROM ? "YES" : "NO",
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Debug email failed",
      smtp: {
        host: process.env.SMTP_HOST ? "YES" : "NO",
        port: process.env.SMTP_PORT || null,
        user: process.env.SMTP_USER ? "YES" : "NO",
        pass: process.env.SMTP_PASS ? "YES" : "NO",
        from: process.env.SMTP_FROM ? "YES" : "NO",
      },
      error: {
        message: error.message,
        code: error.code,
        command: error.command,
        response: error.response,
      },
    });
  }
});

const guestLogin = asyncHandler(async (req, res) => {
  let { username, alias } = req.body;
  if (!username) username = alias;
  if (!username) username = `guest_${Date.now().toString(36)}`;

  username = await ensureUniqueUsername(username);

  const user = await User.create({
    username,
    authProvider: "guest",
    anonymousAlias: randomAlias(),
    privacy: { shareMoodAnalytics: false, allowAnonymousMatching: true },
  });

  await Subscription.create({
    userId: user._id,
    plan: "free",
    status: "free",
    benefits: ["2 free anonymous calls"],
  });

  user.lastAuthAt = new Date();
  await user.save();
  const tokens = issueAuthTokens(user);

  res.status(201).json(buildAuthResponse(user, tokens));
});

const firebaseLogin = asyncHandler(async (req, res) => {
  const { idToken } = req.body;

  if (!idToken) {
    throw new ApiError(400, "idToken is required");
  }

  const decoded = await verifyFirebaseIdToken(idToken);
  const firebaseUid = decoded.uid || decoded.sub;
  if (!firebaseUid) {
    throw new ApiError(401, "Invalid Firebase token");
  }

  const email = decoded.email ? String(decoded.email).toLowerCase() : undefined;
  const displayName = decoded.name || decoded.email?.split("@")[0] || "user";
  const avatarUrl = decoded.picture || undefined;
  const authProvider = decoded.firebase?.sign_in_provider || "firebase";

  let user = await User.findOne({
    $or: [{ firebaseUid }, ...(email ? [{ email }] : [])],
  });

  if (!user) {
    const username = await ensureUniqueUsername(
      (displayName || "user")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "") || `user_${Date.now().toString(36)}`,
    );

    user = await User.create({
      email,
      username,
      displayName,
      avatarUrl,
      firebaseUid,
      authProvider,
      anonymousAlias: randomAlias(),
      isSubscribed: false,
      freeCallsRemaining: 2,
      privacy: { shareMoodAnalytics: false, allowAnonymousMatching: true },
    });

    await Subscription.create({
      userId: user._id,
      plan: "free",
      status: "free",
      benefits: ["2 free anonymous calls"],
    });
  } else {
    const updates = { firebaseUid, authProvider };
    if (email && !user.email) updates.email = email;
    if (displayName && !user.displayName) updates.displayName = displayName;
    if (avatarUrl && !user.avatarUrl) updates.avatarUrl = avatarUrl;
    if (!user.anonymousAlias) updates.anonymousAlias = randomAlias();

    user = await User.findByIdAndUpdate(user._id, updates, {
      returnDocument: "after",
    });
  }

  user.lastAuthAt = new Date();
  await user.save();
  const tokens = issueAuthTokens(user);
  res.json(buildAuthResponse(user, tokens));
});

const refresh = asyncHandler(async (req, res) => {
  const incomingRefreshToken =
    req.body?.refreshToken || req.headers["x-refresh-token"];
  if (!incomingRefreshToken) {
    throw new ApiError(400, "refreshToken is required");
  }

  let payload;
  try {
    payload = verifyRefreshToken(incomingRefreshToken);
  } catch (error) {
    throw new ApiError(401, "Invalid refresh token");
  }
  const user = await User.findById(payload.sub);
  if (!user) {
    throw new ApiError(401, "Invalid refresh token user");
  }
  if (Number(payload.sv || 0) !== Number(user.sessionVersion || 0)) {
    throw new ApiError(401, "Session expired. Please login again.");
  }

  user.lastAuthAt = new Date();
  await user.save();
  const tokens = issueAuthTokens(user);
  res.json(buildAuthResponse(user, tokens));
});

const logout = asyncHandler(async (req, res) => {
  await User.findByIdAndUpdate(req.user._id, {
    $inc: { sessionVersion: 1 },
    $set: { lastAuthAt: new Date() },
  });
  res.json({ success: true, message: "Logged out" });
});

module.exports = {
  register,
  login,
  guestLogin,
  firebaseLogin,
  refresh,
  logout,
  verifyOtp,
  resendOtp,
  debugSendOtpEmail,
};