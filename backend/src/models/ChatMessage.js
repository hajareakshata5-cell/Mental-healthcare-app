const mongoose = require("mongoose");

const chatMessageSchema = new mongoose.Schema(
  {
    roomId: { type: String, required: true, index: true },
    senderAlias: { type: String, required: true },
    recipientAlias: { type: String, required: true },
    body: { type: String, required: true, maxlength: 3000 },
    moderated: {
      flagged: { type: Boolean, default: false },
      reasons: [{ type: String }],
    },
  },
  { timestamps: true },
);

module.exports = mongoose.model("ChatMessage", chatMessageSchema);
