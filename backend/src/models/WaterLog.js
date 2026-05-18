const mongoose = require("mongoose");

const waterLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    date: { type: String, required: true },
    targetMl: { type: Number, required: true },
    consumedMl: { type: Number, default: 0 },
    weather: {
      type: String,
      enum: ["cold", "normal", "hot"],
      default: "normal",
    },
    activityLevel: {
      type: String,
      enum: ["low", "moderate", "high"],
      default: "moderate",
    },
  },
  { timestamps: true },
);

waterLogSchema.index({ userId: 1, date: 1 }, { unique: true });

module.exports = mongoose.model("WaterLog", waterLogSchema);
