const express = require("express");
const { authRequired, requireCallAccess } = require("../middleware/auth");
const { startCall } = require("../controllers/callController");

const router = express.Router();

router.post("/start", authRequired, requireCallAccess, startCall);

module.exports = router;
