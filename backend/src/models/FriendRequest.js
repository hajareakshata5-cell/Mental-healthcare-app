const mongoose = require("mongoose");

const friendRequestSchema = new mongoose.Schema(
  {
    senderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },

    receiverId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },

    status: {
      type: String,
      enum: ["pending", "accepted", "rejected"],
      default: "pending",
      index: true,
    },
  },
  {
    timestamps: true,
  },
);

friendRequestSchema.index(
  { senderId: 1, receiverId: 1 },
  { unique: true },
);


// SCALING_INDEXES_FRIENDREQUEST
friendRequestSchema.index({ receiverId: 1, status: 1, createdAt: -1 });
friendRequestSchema.index({ senderId: 1, status: 1, createdAt: -1 });
friendRequestSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model("FriendRequest", friendRequestSchema);