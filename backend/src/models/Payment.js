const mongoose = require("mongoose");

const paymentSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    amount: { type: Number, required: true, min: 0 },
    currency: { type: String, default: "INR" },
    gateway: {
      type: String,
      enum: ["razorpay", "mock-razorpay", "stripe", "paytm"],
      default: "razorpay",
    },
    plan: {
      type: String,
      enum: ["monthly", "3m", "6m", "12m"],
      default: "3m",
    },
    method: {
      type: String,
      enum: [
        "upi",
        "credit_card",
        "debit_card",
        "net_banking",
        "wallet",
        "gpay",
        "phonepe",
        "paytm",
      ],
      required: true,
    },
    status: {
      type: String,
      enum: ["created", "success", "failed", "refunded"],
      default: "created",
    },
    transactionRef: { type: String, required: true, unique: true },
    razorpayOrderId: { type: String },
    razorpayPaymentId: { type: String },
    razorpaySignature: { type: String },
    invoiceUrl: { type: String },
    verificationAttempts: { type: Number, default: 0 },
    verificationLastAttemptAt: { type: Date },
    verifiedAt: { type: Date },
    failureReason: { type: String },
    lastWebhookEventId: { type: String },
    lastWebhookEventAt: { type: Date },
    providerPayload: { type: mongoose.Schema.Types.Mixed },
  },
  { timestamps: true },
);

paymentSchema.index({ razorpayPaymentId: 1 }, { sparse: true });
paymentSchema.index({ status: 1, updatedAt: -1 });

module.exports = mongoose.model("Payment", paymentSchema);
