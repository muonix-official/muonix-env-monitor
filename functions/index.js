const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.database();

// ─────────────────────────────────────────────
// 1. SCHEDULED: Delete sensor history older than 2 days
//    Runs every day at midnight
// ─────────────────────────────────────────────
exports.deleteOldSensorData = functions.pubsub
  .schedule("0 0 * * *")          // every day at 00:00
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const cutoff = Date.now() - 2 * 24 * 60 * 60 * 1000; // 2 days ago in ms

    const devicesSnap = await db.ref("devices").once("value");
    if (!devicesSnap.exists()) return null;

    const deletePromises = [];

    devicesSnap.forEach((deviceSnap) => {
      const deviceId = deviceSnap.key;
      const historyRef = db.ref(`devices/${deviceId}/history`);

      // Query all history entries with timestamp < cutoff
      const p = historyRef
        .orderByChild("timestamp")
        .endAt(cutoff)
        .once("value")
        .then((oldSnap) => {
          if (!oldSnap.exists()) return;
          const updates = {};
          oldSnap.forEach((entry) => {
            updates[entry.key] = null; // null = delete in Firebase RTDB
          });
          return historyRef.update(updates);
        });

      deletePromises.push(p);
    });

    await Promise.all(deletePromises);
    console.log(`Old sensor data cleaned up (cutoff: ${new Date(cutoff).toISOString()})`);
    return null;
  });

// ─────────────────────────────────────────────
// 2. TRIGGER: Send FCM push when alertLevel changes
//    Listens to devices/{deviceId}/live/alertLevel
// ─────────────────────────────────────────────
exports.sendAlertNotification = functions.database
  .ref("devices/{deviceId}/live/alertLevel")
  .onWrite(async (change, context) => {
    const deviceId = context.params.deviceId;
    const newLevel = change.after.val();
    const prevLevel = change.before.val();

    // Only act if level actually changed
    if (newLevel === prevLevel) return null;

    // Get device info (owner uid + device name)
    const deviceSnap = await db.ref(`devices/${deviceId}`).once("value");
    const device = deviceSnap.val();
    if (!device) return null;

    const ownerUid = device.ownerUid;           // set this when device is registered
    const deviceName = device.name || deviceId;

    // Get owner's FCM token
    const tokenSnap = await db.ref(`users/${ownerUid}/fcmToken`).once("value");
    const token = tokenSnap.val();
    if (!token) return null;

    let title = "";
    let body = "";

    if (newLevel === "warning") {
      title = "⚠️ Warning – " + deviceName;
      body = "Sensor readings are approaching unsafe levels. Please check your environment.";
    } else if (newLevel === "danger") {
      title = "🚨 Danger – " + deviceName;
      body = "Sensor readings are out of the safe zone! Immediate attention required.";
    } else {
      // Readings back to safe — optional, remove if you don't want a "all clear" notification
      title = "✅ Safe – " + deviceName;
      body = "Sensor readings have returned to the safe range.";
    }

    const message = {
      token,
      notification: { title, body },
      android: {
        priority: "high",
        notification: {
          channelId: newLevel === "danger" ? "danger_channel" : "warning_channel",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
      data: {
        deviceId,
        alertLevel: newLevel,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`Notification sent to ${ownerUid} for device ${deviceId}: ${newLevel}`);
    } catch (err) {
      console.error("FCM send error:", err);
    }

    return null;
  });

// ─────────────────────────────────────────────
// 3. TRIGGER: Notify company when user acknowledges danger popup
//    Listens to devices/{deviceId}/live/ackBy/{uid}/seen
// ─────────────────────────────────────────────
exports.onUserAcknowledge = functions.database
  .ref("devices/{deviceId}/live/ackBy/{uid}/seen")
  .onWrite(async (change, context) => {
    const { deviceId, uid } = context.params;
    if (!change.after.val()) return null; // only on set to true

    // Get device and user info
    const [deviceSnap, userSnap] = await Promise.all([
      db.ref(`devices/${deviceId}`).once("value"),
      db.ref(`users/${uid}`).once("value"),
    ]);

    const device = deviceSnap.val();
    const user = userSnap.val();
    if (!device || !user) return null;

    const deviceName = device.name || deviceId;
    const userName = user.displayName || user.email || uid;

    // Write acknowledgment log to company's admin node
    await db.ref(`adminLogs/acknowledgments`).push({
      deviceId,
      deviceName,
      uid,
      userName,
      userEmail: user.email || "",
      userPhone: user.phone || "",
      ts: admin.database.ServerValue.TIMESTAMP,
      seen: true,
    });

    console.log(`ACK logged: user ${uid} acknowledged danger on device ${deviceId}`);
    return null;
  });