const { messaging } = require("../config/firebase");

const sendPushNotification = async ({ token, title, body, data = {} }) => {
  if (!token) {
    console.warn("[push] skipped: missing FCM token");
    return { success: false, message: "Missing FCM token" };
  }

  if (!messaging) {
    console.warn("[push] skipped: Firebase messaging is not initialized");
    return {
      success: false,
      message: "Firebase messaging is not initialized",
    };
  }

  const safeData = Object.fromEntries(
    Object.entries(data || {}).map(([key, value]) => [
      key,
      value == null ? "" : String(value),
    ]),
  );

  const message = {
    token,
    notification: {
      title,
      body,
    },
    data: safeData,
    android: {
      priority: "high",
      ttl: 120000,
      notification: {
        channelId: "incoming_calls",
        priority: "max",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
  };

  const response = await messaging.send(message);

  console.log("[push] sent", {
    tokenPresent: true,
    type: safeData.type,
    response,
  });

  return {
    success: true,
    response,
  };
};

module.exports = {
  sendPushNotification,
};
