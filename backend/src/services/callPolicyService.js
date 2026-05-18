const Subscription = require("../models/Subscription");

const FREE_CALL_LIMIT = 2;

async function canStartCall(user) {
  const subscription = await Subscription.findOne({ userId: user._id });
  const isPremium =
    Boolean(user.isSubscribed) ||
    (subscription &&
      subscription.status === "active" &&
      subscription.plan !== "free");

  if (isPremium) {
    return {
      allowed: true,
      reason: "premium",
      remainingFreeCalls: null,
      isPremium: true,
    };
  }

  const remaining = Math.max(
    typeof user.freeCallsRemaining === "number"
      ? user.freeCallsRemaining
      : FREE_CALL_LIMIT - (user.freeCallQuotaUsed || 0),
    0,
  );
  return {
    allowed: remaining > 0,
    reason: remaining > 0 ? "free_quota" : "quota_exhausted",
    remainingFreeCalls: remaining,
    isPremium: false,
  };
}

module.exports = { canStartCall, FREE_CALL_LIMIT };
