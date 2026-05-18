const mongoose = require("mongoose");

const meditationSessionSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    category: {
      type: String,
      enum: ["sleep", "stress", "focus", "anxiety", "breathing", "mindfulness"],
      required: true,
    },
    durationMinutes: { type: Number, required: true, min: 1 },
    completed: { type: Boolean, default: false },
    recommendedByAI: { type: Boolean, default: false },
  },
  { timestamps: true },
);

module.exports = mongoose.model("MeditationSession", meditationSessionSchema);
