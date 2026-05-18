const WaterLog = require("../models/WaterLog");
const MeditationSession = require("../models/MeditationSession");
const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");
const { buildDailyWellnessPlan } = require("../services/wellnessPlanService");

async function awardHealingProgress(
  userId,
  { xpGain, streakField, achievementLabel },
) {
  const user = await User.findById(userId);
  if (!user) return null;

  const now = new Date();
  const healing = user.healing || {};
  const last = healing.lastHealingActivityAt
    ? new Date(healing.lastHealingActivityAt)
    : null;
  const sameDay = last && last.toDateString() === now.toDateString();
  const currentStreak = Number(healing[streakField] || 0);
  const nextStreak = sameDay ? currentStreak + 1 : 1;
  const nextXp = Number(healing.wellnessXp || 0) + xpGain;
  const nextLevel = Math.max(Math.floor(nextXp / 100) + 1, 1);
  const achievements = new Set(healing.achievements || []);

  if (nextStreak >= 3) achievements.add(`${achievementLabel} Streak`);
  if (nextStreak >= 7) achievements.add(`${achievementLabel} Momentum`);
  if (nextXp >= 500) achievements.add("Healing Champion");

  user.healing = {
    ...healing,
    wellnessXp: nextXp,
    healingLevel: nextLevel,
    [streakField]: nextStreak,
    lastHealingActivityAt: now,
    achievements: Array.from(achievements),
  };
  await user.save();
  return user;
}

function computeWaterTarget(weightKg, age, activityLevel, weather) {
  let baseMl = Math.round(weightKg * 35);
  if (age > 50) baseMl -= 200;
  if (activityLevel === "high") baseMl += 700;
  if (activityLevel === "low") baseMl -= 250;
  if (weather === "hot") baseMl += 400;
  if (weather === "cold") baseMl -= 150;
  return Math.max(baseMl, 1500);
}

const upsertWaterLog = asyncHandler(async (req, res) => {
  const {
    date,
    consumedMl,
    weightKg,
    age,
    activityLevel = "moderate",
    weather = "normal",
  } = req.body;
  const targetMl = computeWaterTarget(weightKg, age, activityLevel, weather);

  const log = await WaterLog.findOneAndUpdate(
    { userId: req.user._id, date },
    { consumedMl, targetMl, weather, activityLevel },
    { upsert: true, returnDocument: "after" },
  );

  await awardHealingProgress(req.user._id, {
    xpGain: 12,
    streakField: "hydrationStreak",
    achievementLabel: "Hydration",
  });

  res.json({ success: true, hydration: log });
});

const createMeditationSession = asyncHandler(async (req, res) => {
  const session = await MeditationSession.create({
    userId: req.user._id,
    category: req.body.category,
    durationMinutes: req.body.durationMinutes,
    completed: !!req.body.completed,
    recommendedByAI: !!req.body.recommendedByAI,
  });

  if (req.body.completed) {
    await awardHealingProgress(req.user._id, {
      xpGain: Math.max(
        18,
        Math.round(Number(req.body.durationMinutes || 0) * 2),
      ),
      streakField: "meditationStreak",
      achievementLabel: "Meditation",
    });
  }

  res.status(201).json({ success: true, session });
});

const dailyPlan = asyncHandler(async (req, res) => {
  const plan = buildDailyWellnessPlan({
    mood: req.user.moodProfile?.baselineMood || "neutral",
    stress: req.user.moodProfile?.stressLevel || 5,
    sleepGoalHours: req.user.wellnessPreferences?.sleepGoalHours || 8,
  });

  res.json({ success: true, plan });
});

module.exports = { upsertWaterLog, createMeditationSession, dailyPlan };
