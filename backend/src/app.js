const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const morgan = require("morgan");
const crypto = require("crypto");

const env = require("./config/env");
const routes = require("./routes");
const packageJson = require("../package.json");
const { apiLimiter } = require("./middleware/rateLimiter");
const { idempotencyMiddleware } = require("./middleware/idempotency");
const { notFound, errorHandler } = require("./middleware/errorHandler");

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
  app.use(apiLimiter);
  app.use(idempotencyMiddleware);

  app.get("/", (_req, res) => {
    res.json({
      name: "Mental Healthcare Backend",
      status: "ok",
      version: "2.0.0",
      docs: "/api/v1",
    });
  });

  app.get("/health", (_req, res) => {
    res.json({ status: "healthy", timestamp: new Date().toISOString() });
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


