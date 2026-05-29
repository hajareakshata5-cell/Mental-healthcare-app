const { messaging } = require("../config/firebase");

const sendPushNotification = async ({
  token,
  title,
  body,
  data = {},
}) => {
  if (!token) {
    return { success: false, message: "Missing FCM token" };
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
  };

  const response = await messaging.send(message);

  return {
    success: true,
    response,
  };
};

module.exports = {
  sendPushNotification,
};