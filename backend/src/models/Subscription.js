const mongoose = require("mongoose");

const subscriptionSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      unique: true,
    },
    plan: {
      type: String,
      enum: ["free", "monthly", "3m", "6m", "12m"],
      default: "free",
    },
    status: {
      type: String,
      enum: ["active", "expired", "cancelled", "free"],
      default: "free",
    },
    startsAt: { type: Date },
    expiresAt: { type: Date },
    autoRenew: { type: Boolean, default: false },
    benefits: [{ type: String }],
  },
  { timestamps: true },
);

module.exports = mongoose.model("Subscription", subscriptionSchema);
