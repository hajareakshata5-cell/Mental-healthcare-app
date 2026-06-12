const rateLimit = require("express-rate-limit");
const Redis = require("ioredis");

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
  store: createRateLimitStore("mindcare_api_rl:"),
  message: {
    success: false,
    message: "Rate limit exceeded. Please retry shortly.",
  },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  store: createRateLimitStore("mindcare_auth_rl:"),
  message: {
    success: false,
    message: "Too many auth attempts. Please try again later.",
  },
});

module.exports = { apiLimiter, authLimiter };
