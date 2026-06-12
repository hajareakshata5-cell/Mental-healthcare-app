const CallLog = require("../models/CallLog");

const CLEANUP_INTERVAL_MS = Number(process.env.CALL_CLEANUP_INTERVAL_MS || 60 * 1000);
const PENDING_TIMEOUT_MS = Number(process.env.CALL_PENDING_TIMEOUT_MS || 2 * 60 * 1000);
const BUSY_TIMEOUT_MS = Number(process.env.CALL_BUSY_TIMEOUT_MS || 2 * 60 * 1000);
const CONNECTED_TIMEOUT_MS = Number(process.env.CALL_CONNECTED_TIMEOUT_MS || 3 * 60 * 60 * 1000);

let cleanupTimer = null;
let cleanupRunning = false;

async function cleanupStaleCallsOnce() {
  if (cleanupRunning) {
    return {
      skipped: true,
      reason: "cleanup already running",
    };
  }

  cleanupRunning = true;

  try {
    const now = new Date();
    const pendingCutoff = new Date(Date.now() - PENDING_TIMEOUT_MS);
    const busyCutoff = new Date(Date.now() - BUSY_TIMEOUT_MS);
    const connectedCutoff = new Date(Date.now() - CONNECTED_TIMEOUT_MS);

    const pendingResult = await CallLog.updateMany(
      {
        status: { $in: ["pending", "ringing"] },
        createdAt: { $lt: pendingCutoff },
      },
      {
        $set: {
          status: "missed",
          endedAt: now,
          systemClosedReason: "stale_pending_cleanup",
        },
      },
    );

    const busyResult = await CallLog.updateMany(
      {
        status: "busy",
        createdAt: { $lt: busyCutoff },
      },
      {
        $set: {
          status: "ended",
          endedAt: now,
          systemClosedReason: "stale_busy_cleanup",
        },
      },
    );

    const connectedResult = await CallLog.updateMany(
      {
        status: { $in: ["accepted", "connected"] },
        updatedAt: { $lt: connectedCutoff },
      },
      {
        $set: {
          status: "ended",
          endedAt: now,
          systemClosedReason: "stale_connected_cleanup",
        },
      },
    );

    const summary = {
      pendingClosed: pendingResult.modifiedCount || 0,
      busyClosed: busyResult.modifiedCount || 0,
      connectedClosed: connectedResult.modifiedCount || 0,
    };

    if (
      summary.pendingClosed > 0 ||
      summary.busyClosed > 0 ||
      summary.connectedClosed > 0
    ) {
      console.log("[call-cleanup] stale calls closed", summary);
    }

    return summary;
  } catch (error) {
    console.error("[call-cleanup] failed", {
      message: error.message,
      stack: error.stack,
    });

    return {
      success: false,
      error: error.message,
    };
  } finally {
    cleanupRunning = false;
  }
}

function startCallCleanupJob() {
  if (cleanupTimer) {
    return cleanupTimer;
  }

  console.log("[call-cleanup] job started", {
    intervalMs: CLEANUP_INTERVAL_MS,
    pendingTimeoutMs: PENDING_TIMEOUT_MS,
    busyTimeoutMs: BUSY_TIMEOUT_MS,
    connectedTimeoutMs: CONNECTED_TIMEOUT_MS,
  });

  cleanupStaleCallsOnce();

  cleanupTimer = setInterval(cleanupStaleCallsOnce, CLEANUP_INTERVAL_MS);

  if (typeof cleanupTimer.unref === "function") {
    cleanupTimer.unref();
  }

  return cleanupTimer;
}

function stopCallCleanupJob() {
  if (cleanupTimer) {
    clearInterval(cleanupTimer);
    cleanupTimer = null;
  }
}

module.exports = {
  startCallCleanupJob,
  stopCallCleanupJob,
  cleanupStaleCallsOnce,
};
