const Subscription = require("../models/Subscription");
const Payment = require("../models/Payment");
const asyncHandler = require("../utils/asyncHandler");
const ApiError = require("../utils/ApiError");
const { canStartCall } = require("../services/callPolicyService");
const {
  hasLifetimeFreeAccess,
  buildLifetimeFreeSubscription,
} = require("../services/lifetimeFreeAccessService");

const plans = {
  "3m": {
    months: 3,
    amountInr: 399,
    benefits: ["Unlimited calls", "Priority matching", "Premium sound therapy"],
  },
  "6m": {
    months: 6,
    amountInr: 599,
    benefits: [
      "Unlimited calls",
      "Priority matching",
      "Premium sound therapy",
      "AI voice access",
    ],
  },
  "12m": {
    months: 12,
    amountInr: 899,
    benefits: [
      "All premium benefits",
      "Advanced AI wellness",
      "Priority support",
    ],
  },
};

const getPlans = asyncHandler(async (req, res) => {
  const plansArray = Object.entries(plans).map(([period, details]) => ({
    period,
    price: details.amountInr,
    months: details.months,
    benefits: details.benefits,
  }));
  res.json({ success: true, plans: plansArray });
});

const getSubscription = asyncHandler(async (req, res) => {
  if (hasLifetimeFreeAccess(req.user)) {
    const subscription = buildLifetimeFreeSubscription(req.user._id);
    return res.json({
      success: true,
      subscription,
      callAccess: {
        allowed: true,
        reason: "lifetime_free_email",
        remainingFreeCalls: null,
        isPremium: true,
      },
      availablePlans: plans,
    });
  }

  const subscription = await Subscription.findOne({ userId: req.user._id });
  const callAccess = await canStartCall(req.user);
  res.json({ success: true, subscription, callAccess, availablePlans: plans });
});

async function buildSubscriptionState(userId, subscription, plan, startsAt) {
  const config = plans[plan];
  if (!config) {
    throw new ApiError(400, "Invalid plan");
  }

  const safeStartsAt = startsAt instanceof Date ? startsAt : new Date(startsAt);
  const expiresAt = new Date(safeStartsAt);
  expiresAt.setMonth(expiresAt.getMonth() + config.months);

  return await Subscription.findOneAndUpdate(
    { userId },
    {
      plan,
      status: "active",
      startsAt: safeStartsAt,
      expiresAt,
      autoRenew: subscription?.autoRenew ?? false,
      benefits: config.benefits,
    },
    { upsert: true, returnDocument: "after" },
  );
}

const activateSubscription = asyncHandler(async (req, res) => {
  const { plan, autoRenew = false } = req.body;
  const config = plans[plan];
  if (!config) {
    return res.status(400).json({ success: false, message: "Invalid plan" });
  }

  const startsAt = new Date();
  const expiresAt = new Date(startsAt);
  expiresAt.setMonth(expiresAt.getMonth() + config.months);

  const subscription = await Subscription.findOneAndUpdate(
    { userId: req.user._id },
    {
      plan,
      status: "active",
      startsAt,
      expiresAt,
      autoRenew,
      benefits: config.benefits,
    },
    { upsert: true, returnDocument: "after" },
  );

  res.json({ success: true, subscription });
});

const restoreSubscription = asyncHandler(async (req, res) => {
  const now = new Date();
  const [subscription, latestPayment] = await Promise.all([
    Subscription.findOne({ userId: req.user._id }),
    Payment.findOne({ userId: req.user._id, status: "success" }).sort({
      verifiedAt: -1,
      updatedAt: -1,
      createdAt: -1,
    }),
  ]);

  if (subscription?.expiresAt && subscription.expiresAt < now) {
    subscription.status = "expired";
    await subscription.save();
  }

  if (
    subscription &&
    subscription.status === "active" &&
    (!subscription.expiresAt || subscription.expiresAt >= now)
  ) {
    await req.user.constructor.findByIdAndUpdate(req.user._id, {
      isSubscribed: true,
      freeCallsRemaining: 999,
    });

    const callAccess = await canStartCall(req.user);
    return res.json({
      success: true,
      restored: true,
      source: "subscription",
      subscription,
      callAccess,
      availablePlans: plans,
    });
  }

  if (latestPayment) {
    const plan = plans[latestPayment.plan] ? latestPayment.plan : "3m";
    const startsAt = latestPayment.verifiedAt || latestPayment.createdAt || now;
    const refreshedSubscription = await buildSubscriptionState(
      req.user._id,
      subscription,
      plan,
      startsAt,
    );

    await req.user.constructor.findByIdAndUpdate(req.user._id, {
      isSubscribed: true,
      freeCallsRemaining: 999,
    });

    const callAccess = await canStartCall(req.user);
    return res.json({
      success: true,
      restored: true,
      source: "payment",
      subscription: refreshedSubscription,
      payment: latestPayment,
      callAccess,
      availablePlans: plans,
    });
  }

  await req.user.constructor.findByIdAndUpdate(req.user._id, {
    isSubscribed: false,
  });

  throw new ApiError(404, "No active subscription or successful payment found");
});

module.exports = {
  getPlans,
  getSubscription,
  activateSubscription,
  restoreSubscription,
};
