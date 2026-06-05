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

   // TEMP: Premium call limit bypassed during testing.
  // Restore canStartCall + freeCallsRemaining logic before production.
  const peerAlias = req.body.peerAlias || req.body.targetUserId || "co_learner";
  const targetUserId = req.body.targetUserId || req.body.receiverId || null;
  const type = req.body.type === "video" ? "video" : "audio";

  const updatedUser = user;
  const isFreeTier = false;
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

const FRIEND_CALL_TIMEOUT_MS = 45 * 1000;

function displayUserName(user) {
  return (
    user?.displayName ||
    user?.username ||
    user?.anonymousAlias ||
    "MindCare user"
  );
}

function isExpiredCall(callLog) {
  return Date.now() - new Date(callLog.createdAt).getTime() > FRIEND_CALL_TIMEOUT_MS;
}

function buildCallJoinPayload({ callLog, currentUser, peerUser }) {
  const uid = agoraUidFromUserId(currentUser._id);
  const token = buildAgoraToken(callLog.channelName, uid);

  return {
    id: callLog._id,
    status: callLog.status,
    channelName: callLog.channelName,
    agoraToken: token,
    agoraUid: uid,
    callType: callLog.type,
    peerName: displayUserName(peerUser),
    peerId: peerUser?._id || null,
  };
}

const requestFriendCall = asyncHandler(async (req, res) => {
  const caller = await User.findById(req.user._id).select("-passwordHash");

  if (!caller) {
    throw new ApiError(404, "User not found");
  }

  const targetUserId = req.body.targetUserId || req.body.receiverId;

  if (!targetUserId) {
    throw new ApiError(400, "targetUserId is required");
  }

  if (targetUserId.toString() === caller._id.toString()) {
    throw new ApiError(400, "You cannot call yourself");
  }

  const receiver = await User.findById(targetUserId).select(
    "-passwordHash",
  );

  if (!receiver) {
    throw new ApiError(404, "Friend not found");
  }

  const type = req.body.type === "video" ? "video" : "audio";

  const channelName = `mindcare_friend_${[
    caller._id.toString(),
    receiver._id.toString(),
  ]
    .sort()
    .join("_")}_${Date.now()}`;

  const callLog = await CallLog.create({
    userId: caller._id,
    targetUserId: receiver._id,
    peerAlias: displayUserName(receiver),
    type,
    durationSeconds: 0,
    status: "pending",
    isFreeTier: false,
    channelName,
  });

  if (
    receiver.fcmToken &&
    receiver.notificationSettings?.pushEnabled !== false &&
    receiver.notificationSettings?.incomingCalls !== false
  ) {
    try {
      await sendPushNotification({
        token: receiver.fcmToken,
        title: "Incoming MindCare Call",
        body: `${displayUserName(caller)} is calling you`,
        data: {
          type: "incoming_call",
          callId: callLog._id.toString(),
          callerId: caller._id.toString(),
          callerName: displayUserName(caller),
          channelName,
          callType: type,
        },
      });
    } catch (error) {
      console.error("[push] friend incoming call failed", error.message);
    }
  }

  return res.status(200).json({
    success: true,
    call: {
      id: callLog._id,
      status: callLog.status,
      peerName: displayUserName(receiver),
      peerId: receiver._id,
      channelName,
      callType: type,
      timeoutSeconds: Math.floor(FRIEND_CALL_TIMEOUT_MS / 1000),
    },
  });
});

const getIncomingFriendCall = asyncHandler(async (req, res) => {
  const receiver = await User.findById(req.user._id).select("-passwordHash");

  if (!receiver) {
    throw new ApiError(404, "User not found");
  }

  const callLog = await CallLog.findOne({
    targetUserId: receiver._id,
    status: "pending",
  })
    .sort({ createdAt: -1 })
    .populate("userId", "username displayName anonymousAlias");

  if (!callLog) {
    return res.status(200).json({
      success: true,
      hasIncomingCall: false,
      call: null,
    });
  }

  if (isExpiredCall(callLog)) {
    callLog.status = "missed";
    await callLog.save();

    return res.status(200).json({
      success: true,
      hasIncomingCall: false,
      call: null,
    });
  }

  return res.status(200).json({
    success: true,
    hasIncomingCall: true,
    call: {
      id: callLog._id,
      status: callLog.status,
      callerId: callLog.userId?._id,
      callerName: displayUserName(callLog.userId),
      channelName: callLog.channelName,
      callType: callLog.type,
      createdAt: callLog.createdAt,
    },
  });
});

const acceptFriendCall = asyncHandler(async (req, res) => {
  const receiver = await User.findById(req.user._id).select("-passwordHash");

  if (!receiver) {
    throw new ApiError(404, "User not found");
  }

  const { callId } = req.body;

  if (!callId) {
    throw new ApiError(400, "callId is required");
  }

  const callLog = await CallLog.findOne({
    _id: callId,
    targetUserId: receiver._id,
    status: "pending",
  }).populate("userId", "username displayName anonymousAlias");

  if (!callLog) {
    throw new ApiError(404, "Incoming call not found");
  }

  if (isExpiredCall(callLog)) {
    callLog.status = "missed";
    await callLog.save();
    throw new ApiError(410, "Call is no longer available");
  }

  callLog.status = "accepted";
  callLog.acceptedAt = new Date();
  await callLog.save();

  return res.status(200).json({
    success: true,
    call: buildCallJoinPayload({
      callLog,
      currentUser: receiver,
      peerUser: callLog.userId,
    }),
  });
});

const rejectFriendCall = asyncHandler(async (req, res) => {
  const { callId } = req.body;

  if (!callId) {
    throw new ApiError(400, "callId is required");
  }

  const callLog = await CallLog.findOne({
    _id: callId,
    targetUserId: req.user._id,
    status: "pending",
  });

  if (!callLog) {
    return res.status(200).json({
      success: true,
      message: "Call already handled",
    });
  }

  callLog.status = "rejected";
  callLog.rejectedAt = new Date();
  await callLog.save();

  return res.status(200).json({
    success: true,
    message: "Call rejected",
  });
});

const cancelFriendCall = asyncHandler(async (req, res) => {
  const { callId } = req.body;

  if (!callId) {
    throw new ApiError(400, "callId is required");
  }

  const callLog = await CallLog.findOne({
    _id: callId,
    userId: req.user._id,
    status: "pending",
  });

  if (!callLog) {
    return res.status(200).json({
      success: true,
      message: "Call already handled",
    });
  }

  callLog.status = "cancelled";
  callLog.cancelledAt = new Date();
  await callLog.save();

  return res.status(200).json({
    success: true,
    message: "Call cancelled",
  });
});

const getFriendCallStatus = asyncHandler(async (req, res) => {
  const callId = req.params.callId;

  const caller = await User.findById(req.user._id).select("-passwordHash");

  if (!caller) {
    throw new ApiError(404, "User not found");
  }

  const callLog = await CallLog.findOne({
    _id: callId,
    userId: caller._id,
  }).populate("targetUserId", "username displayName anonymousAlias");

  if (!callLog) {
    throw new ApiError(404, "Call not found");
  }

  if (callLog.status === "pending" && isExpiredCall(callLog)) {
    callLog.status = "missed";
    await callLog.save();
  }

  const payload = {
    success: true,
    status: callLog.status,
    call: {
      id: callLog._id,
      status: callLog.status,
      peerName: displayUserName(callLog.targetUserId),
      peerId: callLog.targetUserId?._id,
      channelName: callLog.channelName,
      callType: callLog.type,
    },
  };

  if (callLog.status === "accepted" || callLog.status === "connected") {
    payload.call = buildCallJoinPayload({
      callLog,
      currentUser: caller,
      peerUser: callLog.targetUserId,
    });
  }

  return res.status(200).json(payload);
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
    $or: [{ userId: req.user._id }, { targetUserId: req.user._id }],
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
  requestFriendCall,
  getIncomingFriendCall,
  acceptFriendCall,
  rejectFriendCall,
  cancelFriendCall,
  getFriendCallStatus,
  endCall,
  getCallHistory,
  getCallProgress,
};