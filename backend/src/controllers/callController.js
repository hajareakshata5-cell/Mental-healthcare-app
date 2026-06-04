const {
  RtcTokenBuilder,
  RtcRole,
} = require("agora-access-token");
const CallLog = require("../models/CallLog");
const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");
const ApiError = require("../utils/ApiError");
const { canStartCall } = require("../services/callPolicyService");
const { sendPushNotification } = require("../services/notificationService");

const randomMatch = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id).select("-passwordHash");

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  const gender = (req.body.gender || "any").toString().toLowerCase();

    const baseQuery = {
    _id: { $ne: user._id },
    isActive: true,
    isOnlineForMatching: true,
    "privacy.allowAnonymousMatching": { $ne: false },
  };

  async function findCandidate(query) {
    const candidates = await User.aggregate([
      { $match: query },
      { $sample: { size: 1 } },
      {
        $project: {
          _id: 1,
          username: 1,
          displayName: 1,
          anonymousAlias: 1,
          gender: 1,
        },
      },
    ]);

    return candidates[0] || null;
  }

  let peer = null;

  if (gender === "male" || gender === "female") {
    peer = await findCandidate({
      ...baseQuery,
      gender,
    });
  }

  if (!peer) {
    peer = await findCandidate(baseQuery);
  }

  if (!peer) {
    throw new ApiError(404, "No online co-learner available right now");
  }
  

  return res.status(200).json({
    success: true,
    peer: {
      id: peer._id,
      name:
        peer.displayName ||
        peer.username ||
        peer.anonymousAlias ||
        "Co-learner",
      gender: peer.gender || "unknown",
    },
  });
});
function agoraUidFromUserId(userId) {
  const raw = String(userId || "1").replace(/[^a-fA-F0-9]/g, "");
  const shortHex = raw.slice(-8) || "1";
  const parsed = parseInt(shortHex, 16);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 1;
  }

  return (parsed % 2000000000) + 1;
}

function buildAgoraToken(channelName, uid) {
  const appId = process.env.AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE;

  if (!appId || !appCertificate) {
    return "";
  }

  const role = RtcRole.PUBLISHER;
  const expireSeconds = 60 * 60;
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = currentTimestamp + expireSeconds;

  return RtcTokenBuilder.buildTokenWithUid(
    appId,
    appCertificate,
    channelName,
    uid,
    role,
    privilegeExpiredTs,
  );
}
const startCall = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id).select("-passwordHash");

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  const access = await canStartCall(user);

  if (!access.allowed) {
    throw new ApiError(403, "Buy Premium");
  }

  const peerAlias = req.body.peerAlias || req.body.targetUserId || "co_learner";
  const targetUserId = req.body.targetUserId || req.body.receiverId || null;
  const type = req.body.type === "video" ? "video" : "audio";

  let updatedUser = user;
  const isFreeTier = !user.isSubscribed;

  if (!user.isSubscribed) {
    updatedUser = await User.findOneAndUpdate(
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

    if (!updatedUser) {
      throw new ApiError(403, "Buy Premium");
    }
  }

  const channelName = targetUserId
  ? `mindcare_pair_${[updatedUser._id.toString(), targetUserId.toString()]
      .sort()
      .join("_")}`
  : `mindcare_${updatedUser._id}_${Date.now()}`;

const callerAgoraUid = agoraUidFromUserId(updatedUser._id);
const callerAgoraToken = buildAgoraToken(channelName, callerAgoraUid);

const receiverAgoraUid = targetUserId ? agoraUidFromUserId(targetUserId) : 0;
const receiverAgoraToken = targetUserId
  ? buildAgoraToken(channelName, receiverAgoraUid)
  : "";
  console.log("[agora] token-debug", {
  channelName,
  callerAgoraUid,
  receiverAgoraUid,
  callerTokenLength: callerAgoraToken.length,
  receiverTokenLength: receiverAgoraToken.length,
  hasAppId: Boolean(process.env.AGORA_APP_ID),
  hasCertificate: Boolean(process.env.AGORA_APP_CERTIFICATE),
});
  const callLog = await CallLog.create({
    userId: updatedUser._id,
    peerAlias,
    type,
    durationSeconds: 0,
    status: "connected",
    isFreeTier,
    channelName,
    targetUserId,
    
  });

  if (targetUserId) {
    const targetUser = await User.findById(targetUserId).select(
      "fcmToken notificationSettings username displayName anonymousAlias",
    );

    if (
      targetUser &&
      targetUser.fcmToken &&
      targetUser.notificationSettings?.pushEnabled !== false &&
      targetUser.notificationSettings?.incomingCalls !== false
    ) {
      try {
        await sendPushNotification({
          token: targetUser.fcmToken,
          title: "Incoming MindCare Call",
          body: `${updatedUser.displayName || updatedUser.username || "Someone"} is calling you`,
          data: {
            type: "incoming_call",
            callId: callLog._id.toString(),
            callerId: updatedUser._id.toString(),
            callerName:
              updatedUser.displayName ||
              updatedUser.username ||
              updatedUser.anonymousAlias ||
              "MindCare user",
            channelName,
agoraToken: receiverAgoraToken,
agoraUid: String(receiverAgoraUid),
callType: type,
          },
        });
      } catch (error) {
        console.error("[push] incoming call failed", error.message);
      }
    }
  }

  return res.status(200).json({
    success: true,
    call: {
      id: callLog._id,
      allowed: true,
      isPremium: updatedUser.isSubscribed,
      freeCallsRemaining: updatedUser.isSubscribed
        ? 999
        : updatedUser.freeCallsRemaining,
      status: callLog.status,
      peerAlias: callLog.peerAlias,
      channelName,
agoraToken: callerAgoraToken,
agoraUid: callerAgoraUid,
targetUserId,
    },
    user: {
      id: updatedUser._id,
      freeCallsRemaining: updatedUser.isSubscribed
        ? 999
        : updatedUser.freeCallsRemaining,
      isSubscribed: updatedUser.isSubscribed,
    },
  });
});

const endCall = asyncHandler(async (req, res) => {
  const { callId, durationSeconds = 0, rating = 0, feedback = "" } = req.body;

  if (!callId) {
    throw new ApiError(400, "callId is required");
  }

  const safeDuration = Math.max(0, Number(durationSeconds) || 0);
  const safeRating = Math.max(0, Math.min(5, Number(rating) || 0));
  const coinsEarned = Math.max(1, Math.floor(safeDuration / 60));

  const callLog = await CallLog.findOneAndUpdate(
    {
      _id: callId,
      userId: req.user._id,
    },
    {
      durationSeconds: safeDuration,
      status: "ended",
      rating: safeRating,
      feedback: feedback.toString().slice(0, 500),
      coinsEarned,
      endedAt: new Date(),
    },
    { new: true },
  );

  if (!callLog) {
    throw new ApiError(404, "Call not found");
  }

  return res.status(200).json({
    success: true,
    call: callLog,
    reward: {
      coinsEarned,
      durationMinutes: Math.floor(safeDuration / 60),
    },
  });
});

const getCallHistory = asyncHandler(async (req, res) => {
  const calls = await CallLog.find({
    userId: req.user._id,
    status: "ended",
  })
    .sort({ createdAt: -1 })
    .limit(50);

  return res.status(200).json({
    success: true,
    calls,
  });
});

const getCallProgress = asyncHandler(async (req, res) => {
  const calls = await CallLog.find({
    userId: req.user._id,
    status: "ended",
  }).sort({ createdAt: -1 });

  const totalCalls = calls.length;

  const totalSeconds = calls.reduce(
    (sum, call) => sum + (call.durationSeconds || 0),
    0,
  );

  const totalCoins = calls.reduce(
    (sum, call) =>
      sum +
      (call.coinsEarned ||
        Math.max(1, Math.floor((call.durationSeconds || 0) / 60))),
    0,
  );

  const ratedCalls = calls.filter((call) => call.rating && call.rating > 0);

  const averageRating = ratedCalls.length
    ? ratedCalls.reduce((sum, call) => sum + call.rating, 0) / ratedCalls.length
    : 0;

  const now = new Date();
  const weekAgo = new Date(now);
  weekAgo.setDate(now.getDate() - 7);

  const weeklyCalls = calls.filter(
    (call) => new Date(call.createdAt) >= weekAgo,
  );

  return res.status(200).json({
    success: true,
    progress: {
      totalCalls,
      weeklyCalls: weeklyCalls.length,
      totalMinutes: Math.floor(totalSeconds / 60),
      totalCoins,
      averageRating: Number(averageRating.toFixed(1)),
      lastCall: calls[0] || null,
    },
  });
});

module.exports = {
  randomMatch,
  startCall,
  endCall,
  getCallHistory,
  getCallProgress,
};