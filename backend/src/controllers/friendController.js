const FriendRequest = require("../models/FriendRequest");
const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");
const ApiError = require("../utils/ApiError");

const sendFriendRequest = asyncHandler(async (req, res) => {
  const senderId = req.user._id;
  const { receiverId } = req.body;

  if (!receiverId) {
    throw new ApiError(400, "receiverId is required");
  }

  if (senderId.toString() === receiverId.toString()) {
    throw new ApiError(400, "You cannot send request to yourself");
  }

  const receiver = await User.findById(receiverId);
  if (!receiver) {
    throw new ApiError(404, "Receiver not found");
  }

  const existing = await FriendRequest.findOne({
    $or: [
      { senderId, receiverId },
      { senderId: receiverId, receiverId: senderId },
    ],
  });

  if (existing) {
    if (existing.status === "accepted") {
      return res.status(200).json({
        success: true,
        request: existing,
        message: "Already friends",
      });
    }

    if (
      existing.status === "pending" &&
      existing.senderId.toString() === receiverId.toString()
    ) {
      existing.status = "accepted";
      await existing.save();

      return res.status(200).json({
        success: true,
        request: existing,
        message: "Friend request accepted",
      });
    }

    if (existing.status === "rejected") {
      existing.senderId = senderId;
      existing.receiverId = receiverId;
      existing.status = "pending";
      await existing.save();

      return res.status(200).json({
        success: true,
        request: existing,
        message: "Friend request sent again",
      });
    }

    return res.status(200).json({
      success: true,
      request: existing,
      message: "Request already exists",
    });
  }

  const request = await FriendRequest.create({
    senderId,
    receiverId,
    status: "pending",
  });

  return res.status(201).json({
    success: true,
    request,
  });
});
const getFriendRequests = asyncHandler(async (req, res) => {
  const userId = req.user._id;

  const incoming = await FriendRequest.find({
    receiverId: userId,
    status: "pending",
  })
    .populate("senderId", "alias email displayName username")
    .sort({ createdAt: -1 });

  const outgoing = await FriendRequest.find({
    senderId: userId,
    status: "pending",
  })
    .populate("receiverId", "alias email displayName username")
    .sort({ createdAt: -1 });

  return res.status(200).json({
    success: true,
    incoming,
    outgoing,
  });
});

const respondFriendRequest = asyncHandler(async (req, res) => {
  const userId = req.user._id;
  const { requestId, action } = req.body;

  if (!requestId || !action) {
    throw new ApiError(400, "requestId and action are required");
  }

  const request = await FriendRequest.findOne({
    _id: requestId,
    receiverId: userId,
    status: "pending",
  });

  if (!request) {
    throw new ApiError(404, "Friend request not found");
  }

  if (action === "accept") {
    request.status = "accepted";
  } else if (action === "reject") {
    request.status = "rejected";
  } else {
    throw new ApiError(400, "Invalid action");
  }

  await request.save();

  return res.status(200).json({
    success: true,
    request,
  });
});

const getFriends = asyncHandler(async (req, res) => {
  const userId = req.user._id;

  const accepted = await FriendRequest.find({
    status: "accepted",
    $or: [{ senderId: userId }, { receiverId: userId }],
  })
    .populate("senderId", "alias email displayName username")
.populate("receiverId", "alias email displayName username")
    .sort({ updatedAt: -1 });

  const friends = accepted.map((request) => {
    const sender = request.senderId;
    const receiver = request.receiverId;
    return sender._id.toString() === userId.toString() ? receiver : sender;
  });

  return res.status(200).json({
    success: true,
    friends,
  });
});

module.exports = {
  sendFriendRequest,
  getFriendRequests,
  respondFriendRequest,
  getFriends,
};