const express = require("express");

const authRoutes = require("./authRoutes");
const profileRoutes = require("./profileRoutes");
const moodRoutes = require("./moodRoutes");
const callRoutes = require("./callRoutes");
const wellnessRoutes = require("./wellnessRoutes");
const subscriptionRoutes = require("./subscriptionRoutes");
const paymentRoutes = require("./payment");
const emergencyRoutes = require("./emergencyRoutes");

const router = express.Router();

router.use("/auth", authRoutes);
router.use("/profile", profileRoutes);
router.use("/mood", moodRoutes);
router.use("/calls", callRoutes);
router.use("/wellness", wellnessRoutes);
router.use("/subscription", subscriptionRoutes);
router.use("/payment", paymentRoutes);
router.use("/emergency", emergencyRoutes);

module.exports = router;
