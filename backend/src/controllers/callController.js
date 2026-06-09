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

const PRACTICE_MATCH_TIMEOUT_MS = 2 * 60 * 1000;

const randomMatch = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id).select("-passwordHash");

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  const gender = (req.body.gender || "any").toString().toLowerCase();
  const safeGender = gender === "male" || gender === "female" ? gender : "any";
  const cutoff = new Date(Date.now() - PRACTICE_MATCH_TIMEOUT_MS);

  await CallLog.updateMany(
    {
      status: "pending",
      targetUserId: null,
      peerAlias: "Co-learner",
      createdAt: { $lt: cutoff },
    },
    {
      $set: {
        status: "missed",
        endedAt: new Date(),
      },
    },
  );

  const myAcceptedCall = await CallLog.findOne({
    userId: user._id,
    status: "accepted",
    peerAlias: "Co-learner",
    createdAt: { $gte: cutoff },
  })
    .sort({ createdAt: -1 })
    .populate("targetUserId", "username displayName anonymousAlias gender");

  if (myAcceptedCall && myAcceptedCall.targetUserId) {
    return res.status(200).json({
      success: true,
      matched: true,
      role: "caller",
      peer: {
        id: myAcceptedCall.targetUserId._id,
        name: displayUserName(myAcceptedCall.targetUserId),
        gender: myAcceptedCall.targetUserId.gender || "unknown",
      },
      call: buildCallJoinPayload({
        callLog: myAcceptedCall,
        currentUser: user,
        peerUser: myAcceptedCall.targetUserId,
      }),
    });
  }

  async function findWaitingCall(preferredGender) {
    const pipeline = [
      {
        $match: {
          status: "pending",
          targetUserId: null,
          peerAlias: "Co-learner",
          userId: { $ne: user._id },
          createdAt: { $gte: cutoff },
        },
      },
      {
        $lookup: {
          from: "users",
          localField: "userId",
          foreignField: "_id",
          as: "caller",
        },
      },
      { $unwind: "$caller" },
      {
        $match: {
          "caller.isActive": true,
          ...(preferredGender === "male" || preferredGender === "female"
            ? { "caller.gender": preferredGender }
            : {}),
        },
      },
      { $sample: { size: 1 } },
    ];

    const rows = await CallLog.aggregate(pipeline);
    return rows[0] || null;
  }

  let waitingRow = null;

  if (safeGender === "male" || safeGender === "female") {
    waitingRow = await findWaitingCall(safeGender);
  }

  if (!waitingRow) {
    waitingRow = await findWaitingCall("any");
  }

  if (waitingRow) {
    const waitingCall = await CallLog.findOneAndUpdate(
      {
        _id: waitingRow._id,
        status: "pending",
        targetUserId: null,
      },
      {
        $set: {
          targetUserId: user._id,
          status: "accepted",
          acceptedAt: new Date(),
        },
      },
      { new: true },
    ).populate("userId", "username displayName anonymousAlias gender");

    if (waitingCall) {
      return res.status(200).json({
        success: true,
        matched: true,
        role: "receiver",
        peer: {
          id: waitingCall.userId._id,
          name: displayUserName(waitingCall.userId),
          gender: waitingCall.userId.gender || "unknown",
        },
        call: buildCallJoinPayload({
          callLog: waitingCall,
          currentUser: user,
          peerUser: waitingCall.userId,
        }),
      });
    }
  }

  let myWaitingCall = await CallLog.findOne({
    userId: user._id,
    status: "pending",
    targetUserId: null,
    peerAlias: "Co-learner",
    createdAt: { $gte: cutoff },
  });

  if (!myWaitingCall) {
    const channelName = `mindcare_practice_${user._id}_${Date.now()}`;

    myWaitingCall = await CallLog.create({
      userId: user._id,
      targetUserId: null,
      peerAlias: "Co-learner",
      type: "audio",
      durationSeconds: 0,
      status: "pending",
      isFreeTier: false,
      channelName,
      matchGenderPreference: safeGender,
    });
  } else {
    myWaitingCall.matchGenderPreference = safeGender;
    await myWaitingCall.save();
  }

  return res.status(200).json({
    success: true,
    matched: false,
    waitingCallId: myWaitingCall._id,
    message: "Waiting for other co-learners to connect",
    timeoutSeconds: 120,
  });
});

function buildSafeFriendChannelName(callerId, receiverId) {
  const callerPart = String(callerId || "")
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(-6);

  const receiverPart = String(receiverId || "")
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(-6);

  const timePart = Date.now().toString(36);

  return `mcfr_${callerPart}_${receiverPart}_${timePart}`;
}

function agoraUidFromUserId(userId) {
  const raw = String(userId || "1").replace(/[^a-fA-F0-9]/g, "");
  const shortHex = raw.slice(-8) || "1";
  const parsed = parseInt(shortHex, 16);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 1;
  }

  return (parsed % 2000000000) + 1;
}

function cleanEnvValue(value) {
  return String(value || "")
    .trim()
    .replace(/^['"]|['"]$/g, "");
}

function buildAgoraToken(channelName, uid) {
  const appId = cleanEnvValue(process.env.AGORA_APP_ID);
  const appCertificate = cleanEnvValue(process.env.AGORA_APP_CERTIFICATE);
  const safeChannelName = String(channelName || "").trim();
  const safeUid = Number(uid);

  if (!appId || !appCertificate) {
    console.error("[agora] missing credentials", {
      hasAppId: Boolean(appId),
      appIdLength: appId.length,
      hasCertificate: Boolean(appCertificate),
      certificateLength: appCertificate.length,
    });

    throw new ApiError(
      500,
      "Agora calling is not configured on server.",
    );
  }

  if (appId.length !== 32 || appCertificate.length !== 32) {
    console.error("[agora] invalid credential length", {
      appIdLength: appId.length,
      certificateLength: appCertificate.length,
      appIdPreview: appId.slice(0, 6),
    });

    throw new ApiError(
      500,
      "Agora calling credentials are invalid on server.",
    );
  }

  if (!safeChannelName || !Number.isFinite(safeUid) || safeUid <= 0) {
    console.error("[agora] invalid join params", {
      channelNamePresent: Boolean(safeChannelName),
      uid: safeUid,
    });

    throw new ApiError(
      500,
      "Agora call join details are invalid.",
    );
  }

  const role = RtcRole.PUBLISHER;
  const expireSeconds = 60 * 60;
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = currentTimestamp + expireSeconds;

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId,
    appCertificate,
    safeChannelName,
    safeUid,
    role,
    privilegeExpiredTs,
  );

  console.log("[agora] token-built", {
    channelName: safeChannelName,
    uid: safeUid,
    tokenLength: token.length,
    appIdPreview: appId.slice(0, 6),
    hasCertificate: true,
  });

  return token;
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

async function hasActiveFriendCall(userId) {
  const activeCall = await CallLog.findOne({
    status: { $in: ["pending", "accepted", "connected"] },
    $or: [{ userId }, { targetUserId: userId }],
  }).sort({ updatedAt: -1, createdAt: -1 });

  if (!activeCall) return false;

  const lastActivityAt = activeCall.updatedAt || activeCall.acceptedAt || activeCall.createdAt;
  const ageMs = Date.now() - new Date(lastActivityAt).getTime();

  if (activeCall.status === "pending" && ageMs > FRIEND_CALL_TIMEOUT_MS) {
    activeCall.status = "missed";
    activeCall.endedAt = new Date();
    await activeCall.save();
    return false;
  }

  // Safety cleanup: prevents users from being permanently busy after crash/failed join.
  const staleConnectedMs = 90 * 60 * 1000;
  if (
    (activeCall.status === "accepted" || activeCall.status === "connected") &&
    ageMs > staleConnectedMs
  ) {
    activeCall.status = "ended";
    activeCall.endedAt = new Date();
    await activeCall.save();
    return false;
  }

  return true;
}

function hasBlockedBetween(userA, userB) {
  const userABlocks = (userA?.blockedUsers || []).map((id) => id.toString());
  const userBBlocks = (userB?.blockedUsers || []).map((id) => id.toString());

  return (
    userABlocks.includes(userB._id.toString()) ||
    userBBlocks.includes(userA._id.toString())
  );
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

const cleanupStaleFriendCallsForUsers = async (callerId, receiverId) => {
  const now = new Date();

  const shortStaleTime = new Date(Date.now() - 90 * 1000);
  const longStaleTime = new Date(Date.now() - 3 * 60 * 60 * 1000);

  await CallLog.updateMany(
    {
      $or: [
        { userId: callerId },
        { targetUserId: callerId },
        { userId: receiverId },
        { targetUserId: receiverId },
      ],
      status: { $in: ["pending", "ringing"] },
      createdAt: { $lt: shortStaleTime },
    },
    {
      $set: {
        status: "missed",
        endedAt: now,
      },
    },
  );

  await CallLog.updateMany(
    {
      $or: [
        { userId: callerId },
        { targetUserId: callerId },
        { userId: receiverId },
        { targetUserId: receiverId },
      ],
      status: { $in: ["accepted", "connected"] },
      createdAt: { $lt: longStaleTime },
    },
    {
      $set: {
        status: "ended",
        endedAt: now,
      },
    },
  );

  await CallLog.updateMany(
    {
      userId: callerId,
      targetUserId: receiverId,
      status: { $in: ["pending", "ringing", "busy"] },
    },
    {
      $set: {
        status: "cancelled",
        endedAt: now,
      },
    },
  );
};

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

  const receiver = await User.findById(targetUserId).select("-passwordHash");

  if (!receiver) {
    throw new ApiError(404, "Friend not found");
  }

  if (hasBlockedBetween(caller, receiver)) {
  return res.status(403).json({
    success: false,
    status: "blocked",
    message: "You cannot call this user",
  });
}

  await cleanupStaleFriendCallsForUsers(caller._id, receiver._id);

  console.log("[friend-call] stale cleanup done", {
    callerId: caller._id.toString(),
    receiverId: receiver._id.toString(),
  });

  const receiverBusy = await hasActiveFriendCall(receiver._id);

if (receiverBusy) {
  const busyLog = await CallLog.create({
    userId: caller._id,
    targetUserId: receiver._id,
    peerAlias: displayUserName(receiver),
    type: req.body.type === "video" ? "video" : "audio",
    durationSeconds: 0,
    status: "busy",
    isFreeTier: false,
    channelName: "",
  });

  return res.status(200).json({
    success: true,
    status: "busy",
    message: "Your friend is busy currently",
    call: {
      id: busyLog._id,
      status: "busy",
      peerName: displayUserName(receiver),
      peerId: receiver._id,
      callType: busyLog.type,
    },
  });
}

  const type = req.body.type === "video" ? "video" : "audio";

  const channelName = buildSafeFriendChannelName(
  caller._id.toString(),
  receiver._id.toString(),
);

  const callerAgoraUid = agoraUidFromUserId(caller._id);
  const callerAgoraToken = buildAgoraToken(channelName, callerAgoraUid);

  const receiverAgoraUid = agoraUidFromUserId(receiver._id);
  const receiverAgoraToken = buildAgoraToken(channelName, receiverAgoraUid);

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

    console.log("[push] friend call target", {
    receiverId: receiver._id.toString(),
    hasFcmToken: Boolean(receiver.fcmToken),
    pushEnabled: receiver.notificationSettings?.pushEnabled !== false,
    incomingCalls: receiver.notificationSettings?.incomingCalls !== false,
  });

  console.log("[friend-call-debug] receiver push state", {
  receiverId: receiver._id.toString(),
  receiverName: displayUserName(receiver),
  hasFcmToken: Boolean(receiver.fcmToken),
  fcmTokenStart: receiver.fcmToken ? receiver.fcmToken.slice(0, 18) : null,
  pushEnabled: receiver.notificationSettings?.pushEnabled !== false,
  incomingCalls: receiver.notificationSettings?.incomingCalls !== false,
  callId: callLog._id.toString(),
  channelName,
});

  if (
    receiver.fcmToken &&
    receiver.notificationSettings?.pushEnabled !== false &&
    receiver.notificationSettings?.incomingCalls !== false
  ) {
    try {
  const pushResult = await sendPushNotification({
    token: receiver.fcmToken,
    title: "Incoming MindCare Call",
    body: `${displayUserName(caller)} is calling you`,
    data: {
      type: "incoming_call",
      callId: callLog._id.toString(),
      callerId: caller._id.toString(),
      callerName: displayUserName(caller),
      channelName,
      agoraToken: receiverAgoraToken,
      agoraUid: String(receiverAgoraUid),
      callType: type,
    },
  });

  console.log("[friend-call-debug] FCM send success", {
    receiverId: receiver._id.toString(),
    callId: callLog._id.toString(),
    result: pushResult,
  });
} catch (error) {
  console.error("[friend-call-debug] FCM send failed", {
    message: error.message,
    code: error.code,
    stack: error.stack,
  });
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
      agoraToken: callerAgoraToken,
      agoraUid: callerAgoraUid,
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
  .populate("userId", "username displayName anonymousAlias blockedUsers");

  if (!callLog) {
    return res.status(200).json({
      success: true,
      hasIncomingCall: false,
      call: null,
    });
  }

  if (callLog.userId && hasBlockedBetween(receiver, callLog.userId)) {
  callLog.status = "blocked";
  await callLog.save();

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
  status: "ended",
  $or: [{ userId: req.user._id }, { targetUserId: req.user._id }],
})
  .populate("userId", "username displayName anonymousAlias")
  .populate("targetUserId", "username displayName anonymousAlias")
  .sort({ createdAt: -1 })
  .limit(50);
  return res.status(200).json({
    success: true,
    calls,
  });
});

const getCallProgress = asyncHandler(async (req, res) => {
  const calls = await CallLog.find({
  status: "ended",
  $or: [{ userId: req.user._id }, { targetUserId: req.user._id }],
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