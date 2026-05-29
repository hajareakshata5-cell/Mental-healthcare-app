const express = require("express");

const authRoutes = require("./authRoutes");
const profileRoutes = require("./profileRoutes");
const moodRoutes = require("./moodRoutes");
const callRoutes = require("./callRoutes");
const wellnessRoutes = require("./wellnessRoutes");
const chatRoutes = require("./chatRoutes");
const subscriptionRoutes = require("./subscriptionRoutes");
const paymentRoutes = require("./payment");
const emergencyRoutes = require("./emergencyRoutes");
const friendRoutes = require("./friendRoutes");
const userRoutes = require("./userRoutes");
const streakRoutes = require("./streakRoutes");
const notificationRoutes = require("./notificationRoutes");

const router = express.Router();

router.use("/auth", authRoutes);
router.use("/profile", profileRoutes);
router.use("/mood", moodRoutes);
router.use("/calls", callRoutes);
router.use("/wellness", wellnessRoutes);
router.use("/chat", chatRoutes);
router.use("/subscription", subscriptionRoutes);
router.use("/payment", paymentRoutes);
router.use("/emergency", emergencyRoutes);
router.use("/friends", friendRoutes);
router.use("/users", userRoutes);
router.use("/streaks", streakRoutes);
router.use("/notifications", notificationRoutes);

module.exports = router;