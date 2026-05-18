const mongoose = require("mongoose");

const moodLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    mood: {
      type: String,
      enum: ["very_sad", "sad", "low", "neutral", "calm", "happy", "joyful"],
      required: true,
    },
    energy: { type: Number, min: 1, max: 10, required: true },
    stress: { type: Number, min: 1, max: 10, required: true },
    notes: { type: String, maxlength: 1500 },
    aiInsights: [{ type: String }],
    tags: [{ type: String }],
  },
  { timestamps: true },
);

module.exports = mongoose.model("MoodLog", moodLogSchema);
