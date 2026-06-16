const Subscription = require("../models/Subscription");
const { hasLifetimeFreeAccess } = require("./lifetimeFreeAccessService");

const FREE_CALL_LIMIT = 2;

async function canStartCall(user) {
  if (hasLifetimeFreeAccess(user)) {
    return {
      allowed: true,
      reason: "lifetime_free_email",
      remainingFreeCalls: null,
      isPremium: true,
    };
  }

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
