const mongoose = require("mongoose");

const callLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },

    peerAlias: {
      type: String,
      required: true,
    },

    type: {
      type: String,
      enum: ["audio", "video"],
      default: "audio",
    },

    durationSeconds: {
      type: Number,
      default: 0,
    },

    status: {
      type: String,
      enum: ["connected", "ended", "missed", "blocked"],
      required: true,
    },

    isFreeTier: {
      type: Boolean,
      default: true,
    },

    // NEW FIELDS

    rating: {
      type: Number,
      default: 0,
      min: 0,
      max: 5,
    },

    feedback: {
      type: String,
      default: "",
      maxlength: 500,
    },

    coinsEarned: {
      type: Number,
      default: 0,
    },

    endedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("CallLog", callLogSchema);