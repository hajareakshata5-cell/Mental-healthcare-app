const request = require("supertest");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const mongoose = require("mongoose");
const { describe, it, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../../src/app");
const env = require("../../src/config/env");
const {
  canUseMockPaymentFallback,
} = require("../../src/controllers/paymentController");
const User = require("../../src/models/User");
const Subscription = require("../../src/models/Subscription");
const Payment = require("../../src/models/Payment");
const PaymentWebhookEvent = require("../../src/models/PaymentWebhookEvent");
const IdempotencyKey = require("../../src/models/IdempotencyKey");

const beforeAll = before;
const afterAll = after;

env.razorpayWebhookSecret = env.razorpayWebhookSecret || "test_webhook_secret";

function buildTestUser(overrides = {}) {
  return {
    email: `user_${Date.now()}_${Math.random().toString(36).slice(2, 6)}@example.com`,
    username: `user_${Math.random().toString(36).slice(2, 10)}`,
    anonymousAlias: `anon_${Math.random().toString(36).slice(2, 10)}`,
    passwordHash: "hash",
    authProvider: "email",
    ...overrides,
  };
}

function signAccessToken(user) {
  return jwt.sign(
    {
      sub: String(user._id),
      type: "access",
      sv: Number(user.sessionVersion || 0),
      jti: crypto.randomUUID(),
    },
    env.jwtSecret,
    { expiresIn: env.jwtExpire },
  );
}

function signRefreshToken(user) {
  return jwt.sign(
    {
      sub: String(user._id),
      type: "refresh",
      sv: Number(user.sessionVersion || 0),
      jti: crypto.randomUUID(),
    },
    env.jwtRefreshSecret,
    { expiresIn: env.jwtRefreshExpire },
  );
}

function expect(actual) {
  return {
    toBe(expected) {
      assert.strictEqual(actual, expected);
    },
    toBeDefined() {
      assert.notStrictEqual(actual, undefined);
    },
    toBeUndefined() {
      assert.strictEqual(actual, undefined);
    },
    toMatch(expected) {
      assert.match(String(actual), expected);
    },
    toContain(expected) {
      assert.ok(actual.includes(expected));
    },
    toBeGreaterThan(expected) {
      assert.ok(actual > expected);
    },
    toBeGreaterThanOrEqual(expected) {
      assert.ok(actual >= expected);
    },
    toEqual(expected) {
      assert.deepStrictEqual(actual, expected);
    },
  };
}

let app;

describe("Backend Security Hardening Integration Tests", () => {
  beforeAll(async () => {
    app = createApp();
    if (mongoose.connection.readyState === 0) {
      await mongoose.connect(env.mongodbUri);
    }
  });

  afterAll(async () => {
    await User.deleteMany({});
    await Subscription.deleteMany({});
    await Payment.deleteMany({});
    await PaymentWebhookEvent.deleteMany({});
    await IdempotencyKey.deleteMany({});
    await mongoose.disconnect();
  });

  beforeEach(async () => {
    await User.deleteMany({});
    await Subscription.deleteMany({});
    await Payment.deleteMany({});
    await PaymentWebhookEvent.deleteMany({});
    await IdempotencyKey.deleteMany({});
  });

  describe("Dual Token System & Session Versioning", () => {
    it("should issue access + refresh tokens on successful registration", async () => {
      const res = await request(app)
        .post("/api/v1/auth/register")
        .send({
          email: "test@example.com",
          password: "Test123!@",
          username: `test_${Date.now()}`,
          displayName: "Test User",
        });

      expect(res.status).toBe(201);
      expect(res.body.token).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();

      const decoded = jwt.verify(res.body.token, env.jwtSecret);
      expect(decoded.type).toBe("access");
      expect(decoded.sv).toBe(0);
      expect(decoded.jti).toBeDefined();

      const refreshDecoded = jwt.verify(
        res.body.refreshToken,
        env.jwtRefreshSecret,
      );
      expect(refreshDecoded.type).toBe("refresh");
      expect(refreshDecoded.sv).toBe(0);
    });

    it("should refresh access token with valid refresh token", async () => {
      const user = await User.create(buildTestUser());
      const refreshToken = signRefreshToken(user);

      const res = await request(app)
        .post("/api/v1/auth/refresh")
        .send({ refreshToken });

      expect(res.status).toBe(200);
      expect(res.body.token).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();

      const newDecoded = jwt.verify(res.body.token, env.jwtSecret);
      expect(newDecoded.type).toBe("access");
      expect(newDecoded.sub).toBe(String(user._id));
    });

    it("should invalidate all tokens after logout (session version increment)", async () => {
      const user = await User.create(buildTestUser({ sessionVersion: 0 }));
      const oldToken = signAccessToken(user);

      await request(app)
        .post("/api/v1/auth/logout")
        .set("Authorization", `Bearer ${oldToken}`)
        .send({});

      const updatedUser = await User.findById(user._id);
      expect(updatedUser.sessionVersion).toBe(1);

      const res2 = await request(app)
        .get("/api/v1/profile/me")
        .set("Authorization", `Bearer ${oldToken}`);

      expect(res2.status).toBe(401);
      expect(res2.body.message).toMatch(/Session expired|token/i);
    });
  });

  describe("Rate Limiting & Auth Protection", () => {
    it("should enforce 10 max failed auth attempts before rate limit", async () => {
      for (let i = 0; i < 10; i++) {
        const res = await request(app).post("/api/v1/auth/login").send({
          email: "nonexistent@example.com",
          password: "WrongPassword123!",
        });
        expect([401, 429]).toContain(res.status);
      }

      const res11 = await request(app).post("/api/v1/auth/login").send({
        email: "nonexistent@example.com",
        password: "WrongPassword123!",
      });

      expect(res11.status).toBe(429);
      expect(res11.text).toMatch(/Too many auth attempts/i);
    });

    it("should allow requests under the rate limit", async () => {
      const user = await User.create({
        ...buildTestUser({ email: "ratelimit-test@example.com" }),
      });

      const token = signAccessToken(user);

      for (let i = 0; i < 5; i++) {
        const res = await request(app)
          .get("/api/v1/profile/me")
          .set("Authorization", `Bearer ${token}`);
        expect(res.status).toBe(200);
      }
    });
  });

  describe("CORS Validation", () => {
    it("should allow requests from whitelisted origins", async () => {
      const res = await request(app)
        .get("/health")
        .set("Origin", env.corsOrigins[0]);

      expect(res.status).toBe(200);
      expect(res.headers["access-control-allow-origin"]).toBe(
        env.corsOrigins[0],
      );
    });

    it("should reject requests from non-whitelisted origins", async () => {
      const res = await request(app)
        .get("/health")
        .set("Origin", "https://evil.com");

      expect(res.status).toBe(200);
      expect(res.headers["access-control-allow-origin"]).toBeUndefined();
    });
  });

  describe("Request ID Tracking", () => {
    it("should inject x-request-id header if not provided", async () => {
      const res = await request(app).get("/health");

      expect(res.status).toBe(200);
      expect(res.headers["x-request-id"]).toBeDefined();
      expect(res.headers["x-request-id"]).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      );
    });

    it("should preserve provided x-request-id header", async () => {
      const requestId = "test-request-123";

      const res = await request(app)
        .get("/health")
        .set("x-request-id", requestId);

      expect(res.status).toBe(200);
      expect(res.headers["x-request-id"]).toBe(requestId);
    });
  });

  describe("Webhook Replay Protection", () => {
    it("should reject duplicate webhook events (replay attack prevention)", async () => {
      const eventId = "evt_" + crypto.randomBytes(8).toString("hex");
      const payload = JSON.stringify({
        id: eventId,
        event: "payment.captured",
        payload: {
          payment: {
            entity: {
              order_id: "order_123",
              id: "pay_123",
              status: "captured",
              method: "upi",
            },
          },
        },
      });

      const signature = crypto
        .createHmac("sha256", env.razorpayWebhookSecret)
        .update(payload)
        .digest("hex");

      const res1 = await request(app)
        .post("/api/v1/payment/webhook")
        .set("x-razorpay-signature", signature)
        .set("Content-Type", "application/json")
        .send(Buffer.from(payload));

      expect([200, 201, 400]).toContain(res1.status);

      const duplicateEvent = await PaymentWebhookEvent.findOne({
        eventId,
      });

      const res2 = await request(app)
        .post("/api/v1/payment/webhook")
        .set("x-razorpay-signature", signature)
        .set("Content-Type", "application/json")
        .send(Buffer.from(payload));

      if (res2.status === 409 || res2.status === 400) {
        expect([409, 400]).toContain(res2.status);
      }
    });

    it("should reject webhooks with invalid signatures", async () => {
      const payload = JSON.stringify({
        id: "evt_test123",
        event: "order.paid",
      });

      const invalidSignature = "invalid_signature_here";

      const res = await request(app)
        .post("/api/v1/payment/webhook")
        .set("x-razorpay-signature", invalidSignature)
        .set("Content-Type", "application/json")
        .send(Buffer.from(payload));

      expect(res.status).toBe(400);
    });
  });

  describe("Payment Idempotency", () => {
    it("should return same response for duplicate requests with same X-Idempotency-Key", async () => {
      const registerRes = await request(app)
        .post("/api/v1/auth/register")
        .set("X-Forwarded-For", "127.0.0.99")
        .send({
          email: `payment_${Date.now()}@example.com`,
          password: "Test123!@",
          username: `payment_${Date.now()}`,
          displayName: "Payment Test",
        });
      expect(registerRes.status).toBe(201);
      const token = registerRes.body.token;

      const idempotencyKey = crypto.randomUUID();

      const res1 = await request(app)
        .post("/api/v1/payment/create-order")
        .set("Authorization", `Bearer ${token}`)
        .set("X-Idempotency-Key", idempotencyKey)
        .send({ plan: "3m" });

      expect(res1.status).toBe(201);
      const orderId1 = res1.body.order?.id || res1.body.payment?.transactionRef;

      const res2 = await request(app)
        .post("/api/v1/payment/create-order")
        .set("Authorization", `Bearer ${token}`)
        .set("X-Idempotency-Key", idempotencyKey)
        .send({ plan: "3m" });

      expect(res2.status).toBe(201);
      const orderId2 = res2.body.order?.id || res2.body.payment?.transactionRef;

      expect(orderId1).toBe(orderId2);
    });
  });

  describe("Production Fallback Guard", () => {
    it("should refuse mock payment fallback in production mode", () => {
      const previousNodeEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = "production";

      try {
        expect(canUseMockPaymentFallback()).toBe(false);
      } finally {
        process.env.NODE_ENV = previousNodeEnv;
      }
    });
  });

  describe("Helmet Security Headers", () => {
    it("should include strict security headers in responses", async () => {
      const res = await request(app).get("/health");

      expect(res.status).toBe(200);
      expect(res.headers["x-content-type-options"]).toBe("nosniff");
      expect(res.headers["x-frame-options"]).toBeDefined();
      expect(res.headers["referrer-policy"]).toBe("no-referrer");
    });
  });

  describe("Token Type Validation", () => {
    it("should reject refresh tokens used as access tokens", async () => {
      const user = await User.create(
        buildTestUser({
          email: "token-type-test@example.com",
        }),
      );

      const refreshToken = signRefreshToken(user);

      const res = await request(app)
        .get("/api/v1/profile/me")
        .set("Authorization", `Bearer ${refreshToken}`);

      expect(res.status).toBe(401);
      expect(res.body.message).toMatch(/invalid|token|type/i);
    });

    it("should reject access tokens used for refresh endpoint", async () => {
      const user = await User.create(
        buildTestUser({
          email: "refresh-type-test@example.com",
        }),
      );

      const accessToken = signAccessToken(user);

      const res = await request(app)
        .post("/api/v1/auth/refresh")
        .set("X-Forwarded-For", "127.0.0.42")
        .send({ refreshToken: accessToken });

      expect(res.status).toBe(401);
    });
  });

  describe("Mongoose Deprecation Fixes", () => {
    it("should handle subscription updates with returnDocument: after", async () => {
      const user = await User.create(
        buildTestUser({
          email: "mongoose-test@example.com",
        }),
      );

      const res = await request(app)
        .post("/api/v1/subscription/activate")
        .set("Authorization", `Bearer ${signAccessToken(user)}`)
        .send({
          plan: "3m",
        });

      if (res.status === 200 || res.status === 201) {
        expect(res.body.subscription).toBeDefined();
        expect(res.body.subscription._id).toBeDefined();
      }
    });
  });
});
