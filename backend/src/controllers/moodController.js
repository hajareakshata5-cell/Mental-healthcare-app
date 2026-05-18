const MoodLog = require("../models/MoodLog");
const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");

async function awardMoodHealing(userId, mood) {
  const user = await User.findById(userId);
  if (!user) return null;

  const now = new Date();
  const healing = user.healing || {};
  const last = healing.lastHealingActivityAt
    ? new Date(healing.lastHealingActivityAt)
    : null;
  const sameDay = last && last.toDateString() === now.toDateString();
  const currentStreak = Number(healing.moodStreak || 0);
  const nextStreak = sameDay ? currentStreak + 1 : 1;
  const xpGain = mood === "anxious" || mood === "sad" ? 18 : 14;
  const nextXp = Number(healing.wellnessXp || 0) + xpGain;
  const nextLevel = Math.max(Math.floor(nextXp / 100) + 1, 1);
  const achievements = new Set(healing.achievements || []);
  if (nextStreak >= 3) achievements.add("Mood Reset Streak");
  if (nextStreak >= 7) achievements.add("Emotional Consistency");
  if (nextXp >= 250) achievements.add("Healing Momentum");

  user.healing = {
    ...healing,
    wellnessXp: nextXp,
    healingLevel: nextLevel,
    moodStreak: nextStreak,
    lastHealingActivityAt: now,
    achievements: Array.from(achievements),
  };
  await user.save();
  return user;
}

const createMoodLog = asyncHandler(async (req, res) => {
  const { mood, stress, energy, notes, tags } = req.body;
  const log = await MoodLog.create({
    userId: req.user._id,
    mood,
    stress,
    energy,
    notes,
    tags,
    aiInsights: [],
  });

  await awardMoodHealing(req.user._id, mood);

  res.status(201).json({ success: true, moodLog: log });
});

const getMoodHistory = asyncHandler(async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 30), 90);
  const history = await MoodLog.find({ userId: req.user._id })
    .sort({ createdAt: -1 })
    .limit(limit);

  res.json({ success: true, count: history.length, history });
});

module.exports = { createMoodLog, getMoodHistory };
