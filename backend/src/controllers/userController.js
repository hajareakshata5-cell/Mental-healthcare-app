const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");

const getAvailableUsers = asyncHandler(async (req, res) => {
  const currentUserId = req.user._id;

  const currentUser = await User.findById(currentUserId).select("blockedUsers");

  const blockedByMe = (currentUser?.blockedUsers || []).map((id) =>
    id.toString(),
  );

  const users = await User.find({
    _id: {
      $nin: [currentUserId, ...blockedByMe],
    },
    blockedUsers: { $ne: currentUserId },

    // Hide old guest users from practice/available list
    authProvider: { $ne: "guest" },
    username: { $not: /^guest_/i },
  })
    .select("_id alias username email displayName isSubscribed createdAt")
    .sort({ createdAt: -1 })
    .limit(30);

  return res.status(200).json({
    success: true,
    users,
  });
});

module.exports = {
  getAvailableUsers,
};