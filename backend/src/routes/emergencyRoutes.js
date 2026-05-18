const express = require("express");
const { getEmergencyToolkit } = require("../controllers/emergencyController");

const router = express.Router();

router.get("/toolkit", getEmergencyToolkit);

module.exports = router;
