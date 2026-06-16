const CallLog = require("../models/CallLog");
const Subscription = require("../models/Subscription");
const { hasLifetimeFreeAccess } = require("./lifetimeFreeAccessService");

const TRIAL_DAILY_CALL_LIMIT_SECONDS = 30 * 60;
const PREMIUM_SINGLE_CALL_LIMIT_SECONDS = 60 * 60;

function getTodayRange() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);

  const end = new Date(start);
  end.setDate(end.getDate() + 1);

  return { start, end };
}

async function hasPremiumLikeAccess(user) {
  if (hasLifetimeFreeAccess(user)) return true;
  if (user?.isSubscribed) return true;

  const subscription = await Subscription.findOne({ userId: user._id });
  return Boolean(
    subscription &&
      subscription.status === "active" &&
      subscription.plan !== "free" &&
      (!subscription.expiresAt || subscription.expiresAt >= new Date()),
  );
}

async function getTodayCallSeconds(userId) {
  const { start, end } = getTodayRange();

  const rows = await CallLog.aggregate([
    {
      $match: {
        status: "ended",
        endedAt: { $gte: start, $lt: end },
        $or: [{ userId }, { targetUserId: userId }],
      },
    },
    {
      $group: {
        _id: null,
        totalSeconds: { $sum: { $ifNull: ["$durationSeconds", 0] } },
      },
    },
  ]);

  return Number(rows[0]?.totalSeconds || 0);
}

async function buildCallDurationPolicy(user) {
  const isPremium = await hasPremiumLikeAccess(user);

  if (isPremium) {
    return {
      isPremium: true,
      maxCallSeconds: PREMIUM_SINGLE_CALL_LIMIT_SECONDS,
      singleCallLimitSeconds: PREMIUM_SINGLE_CALL_LIMIT_SECONDS,
      dailyLimitSeconds: null,
      dailyUsedSeconds: null,
      dailyRemainingSeconds: null,
      requiresPremiumForMoreCalls: false,
      reason: "premium_one_hour_limit",
      message:
        "Premium calls are unlimited. Each single call can continue up to 1 hour.",
    };
  }

  const dailyUsedSeconds = await getTodayCallSeconds(user._id);
  const dailyRemainingSeconds = Math.max(
    TRIAL_DAILY_CALL_LIMIT_SECONDS - dailyUsedSeconds,
    0,
  );

  return {
    isPremium: false,
    maxCallSeconds: dailyRemainingSeconds,
    singleCallLimitSeconds: dailyRemainingSeconds,
    dailyLimitSeconds: TRIAL_DAILY_CALL_LIMIT_SECONDS,
    dailyUsedSeconds,
    dailyRemainingSeconds,
    requiresPremiumForMoreCalls: dailyRemainingSeconds <= 0,
    reason: "trial_daily_30_min_limit",
    message:
      dailyRemainingSeconds > 0
        ? "Trial users can use 30 minutes of calls per day."
        : "Your daily 30 minutes trial call limit is completed. Take Premium for more calls.",
  };
}

module.exports = {
  TRIAL_DAILY_CALL_LIMIT_SECONDS,
  PREMIUM_SINGLE_CALL_LIMIT_SECONDS,
  buildCallDurationPolicy,
};