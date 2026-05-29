const User = require("../models/User");
const asyncHandler = require("../utils/asyncHandler");

const getAvailableUsers = asyncHandler(async (req, res) => {
  const currentUserId = req.user._id;

  const users = await User.find({
    _id: { $ne: currentUserId },
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