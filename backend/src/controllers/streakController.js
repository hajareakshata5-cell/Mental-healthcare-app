const Streak = require("../models/Streak");
const CallLog = require("../models/CallLog");
const asyncHandler = require("../utils/asyncHandler");

function getTodayKey() {
  return new Date().toISOString().slice(0, 10);
}

function getYesterdayKey() {
  const date = new Date();
  date.setDate(date.getDate() - 1);
  return date.toISOString().slice(0, 10);
}

const getStreak = asyncHandler(async (req, res) => {
  const userId = req.user._id;

  let streak = await Streak.findOne({ userId });

  if (!streak) {
    streak = await Streak.create({ userId });
  }

  return res.status(200).json({
    success: true,
    streak,
  });
});

const completeDailyStreak = asyncHandler(async (req, res) => {
  const userId = req.user._id;
  const today = getTodayKey();
  const yesterday = getYesterdayKey();

  let streak = await Streak.findOne({ userId });

  if (!streak) {
    streak = await Streak.create({ userId });
  }

  if (streak.lastCompletedDate === today) {
    return res.status(200).json({
      success: true,
      streak,
      message: "Streak already completed today",
    });
  }

  const todayStart = new Date(`${today}T00:00:00.000Z`);
  const tomorrowStart = new Date(todayStart);
  tomorrowStart.setDate(tomorrowStart.getDate() + 1);

  const callAgg = await CallLog.aggregate([
    {
      $match: {
        userId,
        status: "ended",
        createdAt: { $gte: todayStart, $lt: tomorrowStart },
      },
    },
    {
      $group: {
        _id: null,
        totalSeconds: { $sum: "$durationSeconds" },
      },
    },
  ]);

  const totalSeconds = callAgg[0]?.totalSeconds || 0;
  const hasThirtyMinCall = totalSeconds >= 30 * 60;

  const waterCompleted =
    req.body.waterCompleted === true ||
    req.body.waterCompleted === "true";

  if (!hasThirtyMinCall || !waterCompleted) {
    return res.status(200).json({
      success: true,
      completed: false,
      reason: "Need 30 minutes call and completed water intake task",
      requirements: {
        callMinutes: Math.floor(totalSeconds / 60),
        waterCompleted,
      },
      streak,
    });
  }

  if (streak.lastCompletedDate === yesterday) {
    streak.currentStreak += 1;
  } else {
    streak.currentStreak = 1;
  }

  streak.longestStreak = Math.max(streak.longestStreak, streak.currentStreak);
  streak.lastCompletedDate = today;
  streak.totalCompletedDays += 1;

  await streak.save();

  return res.status(200).json({
    success: true,
    completed: true,
    streak,
  });
});

module.exports = {
  getStreak,
  completeDailyStreak,
};