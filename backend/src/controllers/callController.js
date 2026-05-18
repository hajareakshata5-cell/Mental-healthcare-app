const CallLog = require("../models/CallLog");
const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");
const ApiError = require("../utils/ApiError");
const { canStartCall } = require("../services/callPolicyService");

const startCall = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id).select("-passwordHash");
  if (!user) {
    throw new ApiError(404, "User not found");
  }

  const access = await canStartCall(user);
  if (!access.allowed) {
    throw new ApiError(403, "Buy Premium");
  }

  const peerAlias = req.body.peerAlias || "ai_support";
  const type = req.body.type === "video" ? "video" : "audio";

  if (!user.isSubscribed) {
    const updated = await User.findOneAndUpdate(
      {
        _id: user._id,
        isSubscribed: false,
        freeCallsRemaining: { $gt: 0 },
      },
      {
        $inc: { freeCallQuotaUsed: 1, freeCallsRemaining: -1 },
      },
      { returnDocument: "after" },
    ).select("-passwordHash");

    if (!updated) {
      throw new ApiError(403, "Buy Premium");
    }

    await CallLog.create({
      userId: updated._id,
      peerAlias,
      type,
      durationSeconds: 0,
      status: "connected",
      isFreeTier: true,
    });

    return res.status(200).json({
      success: true,
      call: {
        allowed: true,
        isPremium: false,
        freeCallsRemaining: updated.freeCallsRemaining,
      },
      user: {
        id: updated._id,
        freeCallsRemaining: updated.freeCallsRemaining,
        isSubscribed: updated.isSubscribed,
      },
    });
  }

  await CallLog.create({
    userId: user._id,
    peerAlias,
    type,
    durationSeconds: 0,
    status: "connected",
    isFreeTier: false,
  });

  return res.status(200).json({
    success: true,
    call: {
      allowed: true,
      isPremium: true,
      freeCallsRemaining: 999,
    },
    user: {
      id: user._id,
      freeCallsRemaining: 999,
      isSubscribed: true,
    },
  });
});

module.exports = { startCall };
