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

function getDayRange(dateKey) {
  const start = new Date(`${dateKey}T00:00:00.000Z`);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start, end };
}

function normalizeStreakBreak(streak) {
  const today = getTodayKey();
  const yesterday = getYesterdayKey();

  if (
    streak.lastCompletedDate &&
    streak.lastCompletedDate !== today &&
    streak.lastCompletedDate !== yesterday
  ) {
    streak.currentStreak = 0;
  }

  if (!Array.isArray(streak.completedDates)) {
    streak.completedDates = [];
  }

  return streak;
}

async function getTodayCallSeconds(userId, today) {
  const { start, end } = getDayRange(today);

  const callAgg = await CallLog.aggregate([
    {
      $match: {
        status: "ended",
        createdAt: { $gte: start, $lt: end },
        $or: [{ userId }, { targetUserId: userId }],
      },
    },
    {
      $group: {
        _id: null,
        totalSeconds: { $sum: "$durationSeconds" },
      },
    },
  ]);

  return callAgg[0]?.totalSeconds || 0;
}

const getStreak = asyncHandler(async (req, res) => {
  const userId = req.user._id;

  let streak = await Streak.findOne({ userId });

  if (!streak) {
    streak = await Streak.create({ userId });
  }

  normalizeStreakBreak(streak);
  await streak.save();

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

  normalizeStreakBreak(streak);

  if (streak.lastCompletedDate === today) {
    return res.status(200).json({
      success: true,
      completed: true,
      streak,
      message: "Streak already completed today",
    });
  }

  const totalSeconds = await getTodayCallSeconds(userId, today);
  const callMinutes = Math.floor(totalSeconds / 60);
  const hasTwentyMinCall = totalSeconds >= 20 * 60;

  const waterCompleted =
    req.body.waterCompleted === true || req.body.waterCompleted === "true";

  const soundCompleted =
    req.body.soundCompleted === true || req.body.soundCompleted === "true";

  if (!hasTwentyMinCall || !waterCompleted || !soundCompleted) {
    return res.status(200).json({
      success: true,
      completed: false,
      reason: "Need water task, sound therapy task, and 20 minutes call",
      requirements: {
        callMinutes,
        waterCompleted,
        soundCompleted,
        hasTwentyMinCall,
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

  if (!streak.completedDates.includes(today)) {
    streak.completedDates.push(today);
    streak.totalCompletedDays = streak.completedDates.length;
  }

  await streak.save();

  return res.status(200).json({
    success: true,
    completed: true,
    message: `Day ${streak.currentStreak} streak completed`,
    requirements: {
      callMinutes,
      waterCompleted,
      soundCompleted,
      hasTwentyMinCall,
    },
    streak,
  });
});

module.exports = {
  getStreak,
  completeDailyStreak,
};