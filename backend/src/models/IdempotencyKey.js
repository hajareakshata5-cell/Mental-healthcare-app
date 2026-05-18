const mongoose = require("mongoose");

const idempotencyKeySchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, index: true },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    method: { type: String, required: true },
    path: { type: String, required: true },
    status: {
      type: Number,
      enum: [200, 201, 400, 401, 403, 404, 409, 422, 500],
      required: true,
    },
    responseBody: { type: mongoose.Schema.Types.Mixed },
    expiresAt: {
      type: Date,
      default: () => new Date(Date.now() + 24 * 60 * 60 * 1000),
    },
  },
  { timestamps: true },
);

idempotencyKeySchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model("IdempotencyKey", idempotencyKeySchema);
