const crypto = require("crypto");
const Razorpay = require("razorpay");
const Payment = require("../models/Payment");
const PaymentAuditLog = require("../models/PaymentAuditLog");
const PaymentWebhookEvent = require("../models/PaymentWebhookEvent");
const Subscription = require("../models/Subscription");
const User = require("../models/User");
const env = require("../config/env");
const asyncHandler = require("../utils/asyncHandler");
const ApiError = require("../utils/ApiError");

function shouldLogPaymentDebug() {
  return (
    process.env.NODE_ENV === "development" &&
    process.env.LOG_AUTH_DEBUG === "true"
  );
}

function canUseMockPaymentFallback() {
  return process.env.NODE_ENV === "development";
}

const PLAN_PRICING = {
  "3m": 399,
  "6m": 599,
  "12m": 899,
};

const DEFAULT_PLAN = "3m";
const PAYMENT_METHODS = new Set([
  "upi",
  "credit_card",
  "debit_card",
  "net_banking",
  "wallet",
  "gpay",
  "phonepe",
  "paytm",
]);

function planAmountInPaise(plan) {
  const inr = PLAN_PRICING[plan] || PLAN_PRICING[DEFAULT_PLAN];
  return inr * 100;
}

function hasRazorpayConfig() {
  return !!(env.razorpayKeyId && env.razorpayKeySecret);
}

function getRazorpayClient() {
  if (!hasRazorpayConfig()) {
    throw new ApiError(500, "Razorpay is not configured");
  }

  return new Razorpay({
    key_id: env.razorpayKeyId,
    key_secret: env.razorpayKeySecret,
  });
}

async function activatePremium(
  userId,
  paymentDoc,
  orderId,
  paymentId,
  signature,
) {
  const startsAt = new Date();
  const plan =
    (paymentDoc && paymentDoc.plan) ||
    (paymentDoc && paymentDoc.notes && paymentDoc.notes.plan) ||
    DEFAULT_PLAN;
  const monthsMap = { "3m": 3, "6m": 6, "12m": 12 };
  const months = monthsMap[plan] || 3;

  const expiresAt = new Date(startsAt);
  expiresAt.setMonth(expiresAt.getMonth() + months);

  const [user, subscription] = await Promise.all([
    User.findByIdAndUpdate(
      userId,
      {
        isSubscribed: true,
        freeCallsRemaining: 999,
      },
      { returnDocument: "after" },
    ).select("-passwordHash"),
    Subscription.findOneAndUpdate(
      { userId },
      {
        plan: plan,
        status: "active",
        startsAt,
        expiresAt,
        autoRenew: false,
        benefits: [
          "Unlimited anonymous calls",
          "Priority matching",
          "Premium sound therapies",
          "Advanced AI wellness features",
          "Exclusive meditation packs",
        ],
      },
      { upsert: true, returnDocument: "after" },
    ),
  ]);

  if (!user || !subscription) {
    throw new ApiError(500, "Unable to activate premium subscription");
  }

  const updatedPayment = await Payment.findByIdAndUpdate(
    paymentDoc._id,
    {
      status: "success",
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
    },
    { returnDocument: "after" },
  );

  return { user, subscription, payment: updatedPayment };
}

async function writePaymentAudit({
  userId,
  paymentId,
  action,
  level = "info",
  message,
  meta,
}) {
  try {
    await PaymentAuditLog.create({
      userId,
      paymentId,
      action,
      level,
      message,
      meta,
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("[payment-audit] failed", error.message);
  }
}

async function buildSuccessPayload({ userId, payment, mockMode, message }) {
  const [user, subscription] = await Promise.all([
    User.findById(userId).select(
      "_id username anonymousAlias isSubscribed freeCallsRemaining",
    ),
    Subscription.findOne({ userId }),
  ]);

  return {
    success: true,
    message,
    mock: mockMode,
    user: user
      ? {
          id: user._id,
          username: user.username,
          alias: user.anonymousAlias,
          isSubscribed: user.isSubscribed,
          freeCallsRemaining: user.freeCallsRemaining,
        }
      : null,
    subscription,
    payment,
  };
}

const createOrder = asyncHandler(async (req, res) => {
  try {
    if (shouldLogPaymentDebug()) {
      // eslint-disable-next-line no-console
      console.log("[payment-debug] createOrder entry", {
        userId: req.user ? String(req.user._id) : null,
        username: req.user?.username,
        authProvider: req.user?.authProvider,
        bodyKeys: req.body ? Object.keys(req.body) : [],
      });
    }
    const userId = req.user._id;
    const plan = (req.body && req.body.plan) || DEFAULT_PLAN;
    if (!PLAN_PRICING[plan]) {
      throw new ApiError(400, "Invalid premium plan");
    }
    const amountPaise = planAmountInPaise(plan);
    const receipt = `premium_${String(userId)}_${plan}_${Date.now()}`;
    const idempotencyKey = req.headers["x-idempotency-key"];

    const requestedMethod = (req.body && req.body.method) || "upi";
    const method = PAYMENT_METHODS.has(requestedMethod)
      ? requestedMethod
      : "upi";

    const mockMode = !hasRazorpayConfig() && canUseMockPaymentFallback();
    let order = null;
    const createMockOrder = () => {
      const seed = idempotencyKey
        ? `${String(userId)}:${plan}:${String(idempotencyKey)}`
        : `${String(userId)}:${plan}:${receipt}`;
      const suffix = crypto
        .createHash("sha256")
        .update(seed)
        .digest("hex")
        .slice(0, 10);

      return {
        id: `order_mock_${suffix}`,
        amount: amountPaise,
        currency: "INR",
        receipt,
        notes: {
          userId: String(userId),
          plan,
        },
        status: "created",
      };
    };

    if (mockMode) {
      order = createMockOrder();
    } else {
      try {
        order = await getRazorpayClient().orders.create({
          amount: amountPaise,
          currency: "INR",
          receipt,
          notes: {
            userId: String(userId),
            plan,
          },
        });
      } catch (error) {
        const isAuthFailure =
          error?.error?.code === "BAD_REQUEST_ERROR" ||
          error?.statusCode === 401 ||
          error?.statusCode === 400;
        if (canUseMockPaymentFallback() && isAuthFailure) {
          if (shouldLogPaymentDebug()) {
            // eslint-disable-next-line no-console
            console.warn(
              "[payment-debug] Razorpay auth failed, falling back to mock order",
              {
                message: error.message,
                statusCode: error.statusCode,
                code: error?.error?.code,
              },
            );
          }
          order = createMockOrder();
        } else {
          throw error;
        }
      }
    }

    let payment;
    payment = await Payment.create({
      userId,
      amount: Math.round((amountPaise || 0) / 100),
      currency: "INR",
      gateway: mockMode ? "mock-razorpay" : "razorpay",
      plan,
      method,
      status: "created",
      transactionRef: order.id,
      razorpayOrderId: order.id,
    });

    res.status(201).json({
      success: true,
      keyId: mockMode ? null : env.razorpayKeyId,
      order,
      payment,
      amount: amountPaise,
      currency: "INR",
      plan,
      method,
      mock: mockMode,
    });
  } catch (error) {
    if (shouldLogPaymentDebug()) {
      // eslint-disable-next-line no-console
      console.error("[payment-debug] createOrder failed", {
        rawType: Object.prototype.toString.call(error),
        rawKeys: error && typeof error === "object" ? Object.keys(error) : [],
        rawValue: error,
        message: error.message,
        name: error.name,
        stack: error.stack,
      });
    }
    throw error;
  }
});

const verifyPayment = asyncHandler(async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } =
    req.body;

  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    throw new ApiError(400, "Missing Razorpay verification data");
  }

  const mockMode = !hasRazorpayConfig() && env.env !== "production";

  const payment = await Payment.findOne({
    transactionRef: razorpay_order_id,
    userId: req.user._id,
  });

  if (!payment) {
    throw new ApiError(404, "Payment record not found");
  }

  payment.verificationAttempts = (payment.verificationAttempts || 0) + 1;
  payment.verificationLastAttemptAt = new Date();
  await payment.save();

  if (payment.status === "success") {
    if (
      payment.razorpayPaymentId &&
      payment.razorpayPaymentId !== razorpay_payment_id
    ) {
      await writePaymentAudit({
        userId: req.user._id,
        paymentId: payment._id,
        action: "verify-conflict",
        level: "error",
        message: "Payment already verified with a different payment id",
        meta: {
          orderId: razorpay_order_id,
          existingPaymentId: payment.razorpayPaymentId,
          incomingPaymentId: razorpay_payment_id,
        },
      });
      throw new ApiError(409, "Payment is already verified");
    }

    const payload = await buildSuccessPayload({
      userId: req.user._id,
      payment,
      mockMode,
      message: "Payment already verified",
    });
    return res.json(payload);
  }

  const duplicatePayment = await Payment.findOne({
    razorpayPaymentId: razorpay_payment_id,
    _id: { $ne: payment._id },
  });
  if (duplicatePayment) {
    payment.status = "failed";
    payment.failureReason = "Duplicate payment id detected";
    await payment.save();
    throw new ApiError(409, "Duplicate payment detected");
  }

  if (!mockMode) {
    const expectedSignature = crypto
      .createHmac("sha256", env.razorpayKeySecret)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest("hex");

    if (expectedSignature !== razorpay_signature) {
      payment.status = "failed";
      payment.razorpayOrderId = razorpay_order_id;
      payment.razorpayPaymentId = razorpay_payment_id;
      payment.razorpaySignature = razorpay_signature;
      payment.failureReason = "Invalid payment signature";
      await payment.save();

      await writePaymentAudit({
        userId: req.user._id,
        paymentId: payment._id,
        action: "verify-signature-failed",
        level: "error",
        message: "Invalid payment signature",
        meta: { orderId: razorpay_order_id, paymentId: razorpay_payment_id },
      });

      throw new ApiError(400, "Invalid payment signature");
    }

    const providerPayment =
      await getRazorpayClient().payments.fetch(razorpay_payment_id);
    const providerAmountInr = Math.round((providerPayment.amount || 0) / 100);
    if (
      providerPayment.order_id !== razorpay_order_id ||
      providerAmountInr !== payment.amount ||
      providerPayment.currency !== payment.currency
    ) {
      payment.status = "failed";
      payment.failureReason = "Payment details mismatch with provider";
      payment.providerPayload = {
        orderId: providerPayment.order_id,
        amount: providerPayment.amount,
        currency: providerPayment.currency,
        status: providerPayment.status,
      };
      await payment.save();
      throw new ApiError(400, "Payment details mismatch");
    }
  }

  payment.status = "success";
  payment.razorpayOrderId = razorpay_order_id;
  payment.razorpayPaymentId = razorpay_payment_id;
  payment.razorpaySignature = razorpay_signature;
  payment.verifiedAt = new Date();
  payment.failureReason = undefined;
  await payment.save();

  const result = await activatePremium(
    req.user._id,
    payment,
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
  );

  await writePaymentAudit({
    userId: req.user._id,
    paymentId: payment._id,
    action: "verify-success",
    message: "Payment verified and premium activated",
    meta: {
      orderId: razorpay_order_id,
      paymentId: razorpay_payment_id,
      plan: payment.plan,
      amount: payment.amount,
    },
  });

  res.json({
    success: true,
    message: "Premium activated",
    mock: mockMode,
    user: {
      id: result.user._id,
      username: result.user.username,
      alias: result.user.anonymousAlias,
      isSubscribed: result.user.isSubscribed,
      freeCallsRemaining: result.user.freeCallsRemaining,
    },
    subscription: result.subscription,
    payment: result.payment,
  });
});

const paymentHistory = asyncHandler(async (req, res) => {
  const rows = await Payment.find({ userId: req.user._id })
    .sort({ createdAt: -1 })
    .limit(100);
  res.json({ success: true, history: rows });
});

const paymentInvoice = asyncHandler(async (req, res) => {
  const payment = await Payment.findOne({
    _id: req.params.paymentId,
    userId: req.user._id,
  }).populate("userId", "username email anonymousAlias");

  if (!payment) {
    throw new ApiError(404, "Invoice not found");
  }

  const subscription = await Subscription.findOne({ userId: req.user._id });
  const startsAt = subscription?.startsAt || payment.createdAt;
  const expiresAt =
    subscription?.expiresAt || payment.updatedAt || payment.createdAt;

  res.json({
    success: true,
    invoice: {
      id: String(payment._id),
      invoiceNumber: `INV-${String(payment._id).slice(-8).toUpperCase()}`,
      paymentId: payment.razorpayPaymentId || payment.transactionRef,
      orderId: payment.razorpayOrderId || payment.transactionRef,
      status: payment.status,
      plan: payment.plan,
      amount: payment.amount,
      currency: payment.currency,
      method: payment.method,
      gateway: payment.gateway,
      createdAt: payment.createdAt,
      user: payment.userId,
      subscription: {
        startsAt,
        expiresAt,
      },
    },
  });
});

const paymentWebhook = asyncHandler(async (req, res) => {
  const signature = req.headers["x-razorpay-signature"];
  const eventIdHeader = req.headers["x-razorpay-event-id"];
  const raw = req.body; // express.raw was used for this route

  if (!env.razorpayWebhookSecret) {
    if (env.env === "production") {
      return res.status(500).json({
        success: false,
        message: "Webhook secret is required in production",
      });
    }
  } else {
    if (!signature) {
      return res
        .status(400)
        .json({ success: false, message: "Missing signature" });
    }
    const expected = crypto
      .createHmac("sha256", env.razorpayWebhookSecret)
      .update(raw)
      .digest("hex");
    if (expected !== signature) {
      return res
        .status(400)
        .json({ success: false, message: "Invalid signature" });
    }
  }

  let payload;
  try {
    payload = JSON.parse(raw.toString());
  } catch (err) {
    return res.status(400).json({ success: false, message: "Invalid payload" });
  }

  const event = payload.event;
  const eventId =
    (eventIdHeader && String(eventIdHeader)) ||
    (payload && payload.id ? String(payload.id) : null) ||
    crypto.createHash("sha256").update(raw).digest("hex");

  const alreadyProcessed = await PaymentWebhookEvent.findOne({ eventId });
  if (alreadyProcessed) {
    return res.json({ success: true, duplicate: true });
  }

  const webhookEvent = await PaymentWebhookEvent.create({
    eventId,
    eventType: event || "unknown",
    signature: signature ? String(signature) : undefined,
    status: "processing",
  });

  // handle payment events
  if (event && event.startsWith("payment.")) {
    const entity =
      payload.payload &&
      payload.payload.payment &&
      payload.payload.payment.entity;
    if (entity) {
      const orderId = entity.order_id;
      const paymentId = entity.id;
      const status = entity.status;
      const method = entity.method;

      const payment = await Payment.findOne({ transactionRef: orderId });
      webhookEvent.orderId = orderId;
      webhookEvent.paymentId = paymentId;
      if (payment) {
        const wasAlreadyCapturedForSamePayment =
          payment.status === "success" &&
          payment.razorpayPaymentId &&
          payment.razorpayPaymentId === paymentId;

        if (
          payment.status === "success" &&
          payment.razorpayPaymentId &&
          payment.razorpayPaymentId !== paymentId
        ) {
          webhookEvent.status = "failed";
          webhookEvent.errorMessage =
            "Payment already captured with different payment id";
          webhookEvent.processedAt = new Date();
          await webhookEvent.save();
          return res.status(409).json({
            success: false,
            message: "Payment already captured",
          });
        }

        payment.razorpayPaymentId = paymentId;
        payment.razorpayOrderId = orderId;
        payment.method = method || payment.method;
        payment.lastWebhookEventId = eventId;
        payment.lastWebhookEventAt = new Date();
        payment.providerPayload = entity;
        payment.status =
          status === "captured"
            ? "success"
            : status === "failed"
              ? "failed"
              : payment.status;
        if (status === "failed") {
          payment.failureReason = "Provider marked payment as failed";
        }
        if (status === "captured") {
          payment.verifiedAt = payment.verifiedAt || new Date();
          payment.failureReason = undefined;
        }
        await payment.save();

        await writePaymentAudit({
          userId: payment.userId,
          paymentId: payment._id,
          action: `webhook-${status || "unknown"}`,
          message: "Processed payment webhook event",
          meta: { orderId, paymentId, method, event, eventId },
        });

        if (status === "captured" && !wasAlreadyCapturedForSamePayment) {
          try {
            await activatePremium(
              payment.userId,
              payment,
              orderId,
              paymentId,
              signature || "",
            );
          } catch (e) {
            // eslint-disable-next-line no-console
            console.error("[webhook] activatePremium failed", e);
          }
        }
      } else {
        webhookEvent.status = "ignored";
        webhookEvent.errorMessage = "No matching payment record found";
      }
    }
  }

  webhookEvent.status =
    webhookEvent.status === "processing" ? "processed" : webhookEvent.status;
  webhookEvent.processedAt = new Date();
  await webhookEvent.save();

  res.json({ success: true });
});

module.exports = {
  createOrder,
  verifyPayment,
  paymentHistory,
  paymentInvoice,
  paymentWebhook,
  canUseMockPaymentFallback,
};
