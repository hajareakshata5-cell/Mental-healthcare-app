const crypto = require("crypto");
const IdempotencyKey = require("../models/IdempotencyKey");

async function idempotencyMiddleware(req, res, next) {
  const key = req.headers["x-idempotency-key"];
  if (!key || !req.user) {
    return next();
  }

  try {
    const existing = await IdempotencyKey.findOne({
      key: String(key),
      userId: req.user._id,
    });

    if (existing) {
      return res.status(existing.status).json(existing.responseBody);
    }

    const originalJson = res.json.bind(res);
    res.json = function (data) {
      const status = res.statusCode;
      IdempotencyKey.create({
        key: String(key),
        userId: req.user._id,
        method: req.method,
        path: req.path,
        status,
        responseBody: data,
      }).catch(() => {});

      return originalJson(data);
    };

    return next();
  } catch (err) {
    return next();
  }
}

async function validateWebhookSignature(
  payload,
  signature,
  secret,
  maxAgeSec = 3600,
) {
  if (!signature || !secret) {
    throw new Error("Missing signature or secret");
  }

  const expectedSignature = crypto
    .createHmac("sha256", secret)
    .update(payload)
    .digest("hex");

  if (expectedSignature !== signature) {
    throw new Error("Invalid webhook signature");
  }

  return true;
}

async function detectWebhookReplay(eventId, maxAgeSec = 900) {
  if (!eventId) {
    throw new Error("Missing event ID");
  }

  const eventHash = crypto.createHash("sha256").update(eventId).digest("hex");
  const cacheKey = `webhook:${eventHash}`;

  return cacheKey;
}

module.exports = {
  idempotencyMiddleware,
  validateWebhookSignature,
  detectWebhookReplay,
};
