const mongoose = require("mongoose");

const paymentWebhookEventSchema = new mongoose.Schema(
  {
    eventId: { type: String, required: true, unique: true, index: true },
    eventType: { type: String, required: true },
    orderId: { type: String },
    paymentId: { type: String },
    signature: { type: String },
    status: {
      type: String,
      enum: ["processing", "processed", "ignored", "duplicate", "failed"],
      default: "processing",
    },
    errorMessage: { type: String },
    processedAt: { type: Date },
  },
  { timestamps: true },
);

module.exports = mongoose.model(
  "PaymentWebhookEvent",
  paymentWebhookEventSchema,
);
