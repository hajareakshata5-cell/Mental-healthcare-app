const mongoose = require("mongoose");

const callLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },

    targetUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
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

    channelName: {
      type: String,
      default: "",
      index: true,
    },

    durationSeconds: {
      type: Number,
      default: 0,
    },

    status: {
      type: String,
      enum: [
        "pending",
        "accepted",
        "connected",
        "ended",
        "rejected",
        "cancelled",
        "missed",
        "blocked",
      ],
      required: true,
    },

    isFreeTier: {
      type: Boolean,
      default: true,
    },

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

    acceptedAt: {
      type: Date,
      default: null,
    },

    rejectedAt: {
      type: Date,
      default: null,
    },

    cancelledAt: {
      type: Date,
      default: null,
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