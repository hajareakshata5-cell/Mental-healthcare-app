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

  const message = {
    token,
    notification: {
      title,
      body,
    },
    data: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, String(value)]),
    ),
    android: {
      priority: "high",
      notification: {
        sound: "default",
      },
    },
  };

  const response = await messaging.send(message);

  console.log("[push] sent", {
    tokenPresent: true,
    type: data.type,
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
