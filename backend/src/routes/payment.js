const express = require("express");
const { authRequired, paymentIdentity } = require("../middleware/auth");
const { idempotencyMiddleware } = require("../middleware/idempotency");
const {
  createOrder,
  verifyPayment,
  paymentHistory,
  paymentInvoice,
  paymentWebhook,
} = require("../controllers/paymentController");

const router = express.Router();

// create-order and verify require client identity (jwt or device)
router.post(
  "/create-order",
  paymentIdentity,
  idempotencyMiddleware,
  createOrder,
);
router.post("/verify", paymentIdentity, idempotencyMiddleware, verifyPayment);
router.get("/history", authRequired, paymentHistory);
router.get("/invoice/:paymentId", authRequired, paymentInvoice);

// Razorpay webhook endpoint (raw body required for signature verification)
router.post(
  "/webhook",
  express.raw({ type: "application/json" }),
  paymentWebhook,
);

module.exports = router;
