const rateLimitModule = require("express-rate-limit");
const Redis = require("ioredis");

const rateLimit = rateLimitModule.rateLimit || rateLimitModule;
const ipKeyGenerator =
  rateLimitModule.ipKeyGenerator ||
  ((ip) => String(ip || "unknown").replace(/:\d+[^:]*$/, ""));

let redisClient = null;

function getRedisClient() {
  const redisUrl = process.env.REDIS_URL || process.env.UPSTASH_REDIS_URL;

  if (!redisUrl) {
    return null;
  }

  if (!redisClient) {
    redisClient = new Redis(redisUrl, {
      maxRetriesPerRequest: 2,
      tls: redisUrl.startsWith("rediss://") ? {} : undefined,
    });

    redisClient.on("error", (error) => {
      console.error("[rate-limit] Redis error:", error.message);
    });
  }

  return redisClient;
}

function cleanKey(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9@._:-]/g, "_")
    .slice(0, 160);
}

function getClientIp(req) {
  const forwardedFor = req.headers["x-forwarded-for"];
  const forwardedIp = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : String(forwardedFor || "").split(",")[0].trim();

  return (
    forwardedIp ||
    req.headers["x-real-ip"] ||
    req.socket?.remoteAddress ||
    req.connection?.remoteAddress ||
    "unknown"
  );
}

function getDeviceId(req) {
  return (
    req.headers["x-device-id"] ||
    req.headers["x-client-device-id"] ||
    req.body?.deviceId ||
    req.query?.deviceId ||
    ""
  );
}

function getBearerFingerprint(req) {
  const header = req.headers.authorization || "";
  if (!header.startsWith("Bearer ")) {
    return "";
  }

  // Full token key मध्ये ठेवायचा नाही. फक्त छोटा fingerprint वापरतो.
  const token = header.slice(7).trim();
  if (!token) return "";

  return token.slice(-24);
}

function authKeyGenerator(req) {
  const email = cleanKey(req.body?.email);
  const username = cleanKey(req.body?.username);
  const firebaseUid = cleanKey(req.body?.firebaseUid || req.body?.uid);
  const deviceId = cleanKey(getDeviceId(req));

  if (email) return `auth_email:${email}`;
  if (firebaseUid) return `auth_firebase:${firebaseUid}`;
  if (username) return `auth_username:${username}`;
  if (deviceId) return `auth_device:${deviceId}`;

  return `auth_ip:${ipKeyGenerator(getClientIp(req))}`;
}

function apiKeyGenerator(req) {
  const userId = cleanKey(req.user?._id || req.auth?.sub);
  const deviceId = cleanKey(getDeviceId(req));
  const bearerFingerprint = cleanKey(getBearerFingerprint(req));

  if (userId) return `api_user:${userId}`;
  if (deviceId) return `api_device:${deviceId}`;
  if (bearerFingerprint) return `api_token:${bearerFingerprint}`;

  return `api_ip:${ipKeyGenerator(getClientIp(req))}`;
}

class MindCareRedisStore {
  constructor(prefix) {
    this.prefix = prefix;
    this.windowMs = 15 * 60 * 1000;
  }

  init(options) {
    this.windowMs = options.windowMs;
  }

  async increment(key) {
    const redis = getRedisClient();

    if (!redis) {
      throw new Error("Redis client is not configured");
    }

    const redisKey = `${this.prefix}${key}`;
    const totalHits = await redis.incr(redisKey);

    if (totalHits === 1) {
      await redis.pexpire(redisKey, this.windowMs);
    }

    let ttl = await redis.pttl(redisKey);

    if (ttl < 0) {
      ttl = this.windowMs;
      await redis.pexpire(redisKey, this.windowMs);
    }

    return {
      totalHits,
      resetTime: new Date(Date.now() + ttl),
    };
  }

  async decrement(key) {
    const redis = getRedisClient();
    if (!redis) return;

    const redisKey = `${this.prefix}${key}`;
    const current = await redis.decr(redisKey);

    if (current <= 0) {
      await redis.del(redisKey);
    }
  }

  async resetKey(key) {
    const redis = getRedisClient();
    if (!redis) return;

    await redis.del(`${this.prefix}${key}`);
  }
}

function createRateLimitStore(prefix) {
  const redis = getRedisClient();

  if (!redis) {
    console.warn(`[rate-limit] REDIS_URL not set. Using in-memory limiter for ${prefix}.`);
    return undefined;
  }

  return new MindCareRedisStore(prefix);
}

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 2000,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: apiKeyGenerator,
  store: createRateLimitStore("mindcare_api_rl:"),
  message: {
    success: false,
    message: "Rate limit exceeded. Please retry shortly.",
  },
});


const callApiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 240,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: apiKeyGenerator,
  store: createRateLimitStore("mindcare_call_rl:"),
  message: {
    success: false,
    message: "Call service is busy. Please wait a few seconds and try again.",
  },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  keyGenerator: authKeyGenerator,
  store: createRateLimitStore("mindcare_auth_rl:"),
  message: {
    success: false,
    message: "Too many auth attempts. Please try again later.",
  },
});

module.exports = { apiLimiter, authLimiter, callApiLimiter };
