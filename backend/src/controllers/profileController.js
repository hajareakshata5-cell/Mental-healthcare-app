const User = require("../models/User");
const Subscription = require("../models/Subscription");
const asyncHandler = require("../utils/asyncHandler");

const getMe = asyncHandler(async (req, res) => {
  const subscription = await Subscription.findOne({ userId: req.user._id });
  res.json({
    success: true,
    profile: {
      ...req.user.toObject(),
      passwordHash: undefined,
      subscription: subscription || { plan: "free", status: "free" },
    },
  });
});

const updateMe = asyncHandler(async (req, res) => {
  const updates = {};
  const allowed = [
    "displayName",
    "avatarUrl",
    "wellnessPreferences",
    "privacy",
    "moodProfile",
  ];

  allowed.forEach((key) => {
    if (req.body[key] !== undefined) {
      updates[key] = req.body[key];
    }
  });

  const updated = await User.findByIdAndUpdate(req.user._id, updates, {
    new: true,
  }).select("-passwordHash");

  res.json({ success: true, profile: updated });
});

module.exports = { getMe, updateMe };
