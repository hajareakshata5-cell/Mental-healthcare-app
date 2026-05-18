const express = require("express");
const { authRequired } = require("../middleware/auth");
const {
  getPlans,
  getSubscription,
  activateSubscription,
  restoreSubscription,
} = require("../controllers/subscriptionController");

const router = express.Router();

router.get("/plans", authRequired, getPlans);
router.get("/", authRequired, getSubscription);
router.post("/activate", authRequired, activateSubscription);
router.post("/restore", authRequired, restoreSubscription);

module.exports = router;
