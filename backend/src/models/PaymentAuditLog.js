const mongoose = require("mongoose");

const paymentAuditLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      index: true,
    },
    paymentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Payment",
      index: true,
    },
    action: { type: String, required: true, index: true },
    level: {
      type: String,
      enum: ["info", "warn", "error"],
      default: "info",
    },
    message: { type: String },
    meta: { type: mongoose.Schema.Types.Mixed },
  },
  { timestamps: true },
);

paymentAuditLogSchema.index({ createdAt: -1 });

module.exports = mongoose.model("PaymentAuditLog", paymentAuditLogSchema);
