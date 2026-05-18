const ApiError = require("../utils/ApiError");
const User = require("../models/User");
const { verifyAccessToken } = require("../services/tokenService");

function shouldLogAuthDebug() {
  return (
    process.env.NODE_ENV === "development" &&
    process.env.LOG_AUTH_DEBUG === "true"
  );
}

function getDeviceId(req) {
  return (
    req.headers["x-device-id"] ||
    req.body?.deviceId ||
    req.query?.deviceId ||
    null
  );
}

async function findOrCreateGuestUser(deviceId) {
  const existing = await User.findOne({ deviceId }).select("-passwordHash");
  if (existing) {
    return existing;
  }

  const suffix =
    deviceId.replace(/[^a-zA-Z0-9]/g, "").slice(-8) || Date.now().toString(36);
  const username = `guest_${suffix}`;
  const anonymousAlias = `anon_${suffix}`;

  const created = await User.create({
    username,
    deviceId,
    authProvider: "guest",
    anonymousAlias,
    freeCallsRemaining: 2,
    freeCallQuotaUsed: 0,
    privacy: { shareMoodAnalytics: false, allowAnonymousMatching: true },
  });

  return created.toObject ? created : created;
}

async function authRequired(req, _res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return next(new ApiError(401, "Missing bearer token"));
  }

  try {
    const token = header.slice(7);
    const payload = verifyAccessToken(token);
    if (shouldLogAuthDebug()) {
      // eslint-disable-next-line no-console
      console.log("[auth-debug] decoded payload", {
        sub: payload.sub,
        type: payload.type,
        sv: payload.sv,
        jti: payload.jti,
      });
    }
    const user = await User.findById(payload.sub).select("-passwordHash");
    if (!user) {
      return next(new ApiError(401, "Invalid token user"));
    }
    if (Number(payload.sv || 0) !== Number(user.sessionVersion || 0)) {
      return next(new ApiError(401, "Session expired. Please login again."));
    }

    req.user = user;
    req.auth = payload;
    if (shouldLogAuthDebug()) {
      // eslint-disable-next-line no-console
      console.log("[auth-debug] req.user", {
        id: String(user._id),
        username: user.username,
        authProvider: user.authProvider,
        isSubscribed: user.isSubscribed,
        freeCallsRemaining: user.freeCallsRemaining,
      });
    }
    return next();
  } catch (error) {
    return next(new ApiError(401, "Invalid or expired token"));
  }
}

async function requireCallAccess(req, _res, next) {
  try {
    if (req.user?.isSubscribed) {
      return next();
    }

    if ((req.user?.freeCallsRemaining ?? 0) <= 0) {
      return next(new ApiError(403, "Buy Premium"));
    }

    return next();
  } catch (error) {
    return next(error);
  }
}

async function paymentIdentity(req, _res, next) {
  const header = req.headers.authorization;
  if (header && header.startsWith("Bearer ")) {
    if (shouldLogAuthDebug()) {
      // eslint-disable-next-line no-console
      console.log("[payment-debug] using bearer auth for payment route");
    }
    return authRequired(req, _res, next);
  }

  try {
    const deviceId = getDeviceId(req);
    if (!deviceId) {
      return next(new ApiError(401, "Missing bearer token or deviceId"));
    }

    const user = await findOrCreateGuestUser(deviceId);
    req.user = user;
    req.deviceId = deviceId;
    if (shouldLogAuthDebug()) {
      // eslint-disable-next-line no-console
      console.log("[payment-debug] using device auth for payment route", {
        deviceId,
        userId: String(user._id),
        username: user.username,
      });
    }
    return next();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  authRequired,
  requireCallAccess,
  paymentIdentity,
  getDeviceId,
};
