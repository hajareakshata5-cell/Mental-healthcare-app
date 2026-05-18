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

function randomAlias() {
  return `anon_${Math.random().toString(36).slice(2, 10)}`;
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

  const existing = await User.findOne({ $or: [{ email }, { username }] });
  if (existing) {
    throw new ApiError(
      409,
      "User already exists with provided email or username",
    );
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({
    email,
    username,
    displayName,
    passwordHash,
    authProvider: "email",
    anonymousAlias: randomAlias(),
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

const login = asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    throw new ApiError(400, "email and password are required");
  }

  const user = await User.findOne({ email });
  if (!user || !user.passwordHash) {
    throw new ApiError(401, "Invalid credentials");
  }

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    throw new ApiError(401, "Invalid credentials");
  }

  user.lastAuthAt = new Date();
  await user.save();
  const tokens = issueAuthTokens(user);

  res.json(buildAuthResponse(user, tokens));
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
};
