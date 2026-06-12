const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendAlertNotification = functions.database
  .ref("/devices/{deviceId}/live/alert")
  .onWrite(async (change, context) => {
    const alertValue = change.after.val();
    const deviceId = context.params.deviceId;

    // Only send notification when alert turns ON
    if (alertValue !== true) return null;

    // Get live data
    const liveSnap = await admin
      .database()
      .ref(`/devices/${deviceId}/live`)
      .once("value");
    const live = liveSnap.val();

    if (!live) return null;

    const temp = live.temp || 0;
    const humidity = live.humidity || 0;

    // Get FCM token
    const tokenSnap = await admin
      .database()
      .ref(`/devices/${deviceId}/meta/fcm_token`)
      .once("value");
    const token = tokenSnap.val();

    if (!token) {
      console.log("No FCM token found for device:", deviceId);
      return null;
    }

    // Send notification
    const message = {
      token: token,
      notification: {
        title: "⚠️ SensorBox Alert!",
        body: `Unsafe conditions! Temp: ${temp.toFixed(1)}°C, Humidity: ${humidity.toFixed(1)}%`,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          priority: "high",
          channelId: "sensorbox_alerts",
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log("Notification sent successfully!");
    } catch (error) {
      console.error("Error sending notification:", error);
    }

    return null;
  });