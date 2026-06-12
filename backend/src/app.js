const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const morgan = require("morgan");
const crypto = require("crypto");
const mongoose = require("mongoose");

const env = require("./config/env");
const routes = require("./routes");
const packageJson = require("../package.json");
const { apiLimiter, getRedisClient } = require("./middleware/rateLimiter");
const { idempotencyMiddleware } = require("./middleware/idempotency");
const { notFound, errorHandler } = require("./middleware/errorHandler");


function shouldSkipGlobalApiLimiter(req) {
  return req.path.startsWith("/api/v1/calls");
}

function createApp() {
  const app = express();
  const jsonParser = express.json({ limit: "1mb" });
  const allowedOrigins = new Set(env.corsOrigins);

  app.locals.routeManifest = {
    app: "mentalhealth-backend",
    routes: [
      "GET /",
      "GET /health",
      "GET /deployment-version",
      "POST /api/v1/auth/register",
      "POST /api/v1/auth/login",
      "POST /api/v1/auth/guest",
      "POST /api/v1/auth/firebase",
      "GET /api/v1/auth/me",
      "GET /api/v1/profile/me",
      "GET /api/v1/mood",
      "POST /api/v1/mood",
      "POST /api/v1/chat/respond",
      "POST /api/v1/calls/friend/request",
      "GET /api/v1/calls/friend/incoming",
      "POST /api/v1/calls/friend/accept",
      "POST /api/v1/calls/friend/reject",
      "POST /api/v1/calls/friend/cancel",
      "GET /api/v1/calls/friend/status/:callId",
      "POST /api/v1/notifications/save-token",
      "GET /api/v1/payment/invoice/:paymentId",
      "GET /api/v1/payment/history",
      "POST /api/v1/payment/verify",
      "POST /api/v1/payment/create-order",
      "POST /api/v1/subscription/restore",
      "POST /api/v1/subscription/activate",
      "GET /api/v1/subscription",
      "socket.io /",
    ],
  };

  app.set("trust proxy", env.trustedProxy);

  app.use(
    helmet({
      contentSecurityPolicy: false,
      referrerPolicy: { policy: "no-referrer" },
      hsts: env.env === "production",
      crossOriginResourcePolicy: { policy: "cross-origin" },
    }),
  );
  app.use((req, res, next) => {
    req.requestId = req.headers["x-request-id"] || crypto.randomUUID();
    res.setHeader("x-request-id", req.requestId);
    next();
  });
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin) {
          callback(null, true);
          return;
        }
        callback(null, allowedOrigins.has(origin));
      },
      credentials: true,
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      allowedHeaders: [
        "Content-Type",
        "Authorization",
        "X-Device-Id",
        "X-Idempotency-Key",
        "X-Refresh-Token",
        "X-Request-Id",
      ],
    }),
  );
  app.use((req, res, next) => {
    if (req.path === "/api/v1/payment/webhook") {
      return next();
    }
    return jsonParser(req, res, next);
  });
  morgan.token("requestId", (req) => req.requestId);
  app.use(morgan(env.env === "production" ? "combined" : "dev"));
  app.use((req, res, next) => {
    if (shouldSkipGlobalApiLimiter(req)) {
      return next();
    }

    return apiLimiter(req, res, next);
  });
  app.use(idempotencyMiddleware);

  app.get("/", (_req, res) => {
    res.json({
      name: "Mental Healthcare Backend",
      status: "ok",
      version: "2.0.0",
      docs: "/api/v1",
    });
  });

  app.get("/health", async (_req, res) => {
    const startedAt = Date.now();

    const mongoStateMap = {
      0: "disconnected",
      1: "connected",
      2: "connecting",
      3: "disconnecting",
    };

    const mongo = {
      status: mongoStateMap[mongoose.connection.readyState] || "unknown",
      ok: mongoose.connection.readyState === 1,
    };

    if (mongo.ok && mongoose.connection.db) {
      try {
        await mongoose.connection.db.admin().ping();
      } catch (error) {
        mongo.ok = false;
        mongo.error = error.message;
      }
    }

    const redis = {
      configured: Boolean(process.env.REDIS_URL || process.env.UPSTASH_REDIS_URL),
      ok: false,
      status: "not_configured",
    };

    if (redis.configured) {
      try {
        const client = getRedisClient();
        const pong = await Promise.race([
          client.ping(),
          new Promise((_, reject) =>
            setTimeout(() => reject(new Error("Redis ping timeout")), 1500),
          ),
        ]);

        redis.ok = pong === "PONG";
        redis.status = redis.ok ? "connected" : "unexpected_response";
      } catch (error) {
        redis.ok = false;
        redis.status = "error";
        redis.error = error.message;
      }
    }

    const healthy = mongo.ok && (!redis.configured || redis.ok);

    return res.status(healthy ? 200 : 503).json({
      status: healthy ? "healthy" : "degraded",
      service: "mentalhealth-backend",
      version: packageJson.version,
      timestamp: new Date().toISOString(),
      uptimeSeconds: Math.floor(process.uptime()),
      responseTimeMs: Date.now() - startedAt,
      checks: {
        mongo,
        redis,
      },
    });
  });

  app.get("/deployment-version", (_req, res) => {
    res.json({
      app: "mentalhealth-backend",
      routes: "full-api",
      version: packageJson.version,
      timestamp: new Date().toISOString(),
    });
  });

  app.use("/api/v1", routes);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}

module.exports = { createApp };


