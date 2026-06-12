# Muonix EnvGuard

An industrial-grade IoT environment monitoring app built with Flutter and Firebase. Monitor real-time temperature, humidity, and gas levels from your devices — with instant alerts when values exceed safe ranges.

---

## Features

- 📱 **QR Code Device Pairing** — scan the QR code on your IoT device to instantly connect
- 🌡️ **Real-time Monitoring** — live temperature, humidity, and gas level readings
- 🚨 **Instant Alerts** — push notifications when sensor values exceed your set thresholds
- 📊 **History** — view past sensor readings over time
- ⚙️ **Custom Thresholds** — adjust safe range limits per device from the app
- 🔐 **Secure Login** — email-based authentication via Firebase Auth
- 📲 **Multi-device Support** — add and manage multiple devices from one account

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter (Dart) |
| Backend / Database | Firebase Realtime Database |
| Authentication | Firebase Auth |
| Notifications | Firebase Cloud Messaging (FCM) |
| Hardware | Arduino with DHT sensor + MQ-6 gas sensor |
| IDE | VS Code + Arduino IDE |

---

## Hardware

- **Microcontroller** — Arduino
- **Temperature & Humidity** — DHT sensor (3-pin)
- **Gas Detection** — MQ-6 sensor
- Sensor data is pushed to Firebase Realtime Database over Wi-Fi

---

## Screenshots

> Coming soon

---

## Getting Started

### Prerequisites
- Flutter SDK installed
- Firebase project set up
- Android Studio or VS Code

### Setup

1. Clone the repository
   ```bash
   git clone https://github.com/muonix-official/muonix-env-monitor.git
   cd muonix-env-monitor
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Add your Firebase configuration
   - Download `google-services.json` from your Firebase console
   - Place it in `android/app/`
   - Download `GoogleService-Info.plist` for iOS and place it in `ios/Runner/`

4. Run the app
   ```bash
   flutter run
   ```

---

## Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Authentication** → Email/Password
3. Enable **Realtime Database**
4. Set up **Cloud Messaging** for push notifications
5. Add your Android and iOS apps to the Firebase project

---

## Security

- `google-services.json` and `GoogleService-Info.plist` are excluded from this repository
- Firebase Realtime Database rules are configured to allow only authenticated users
- All sensor data is transmitted securely over HTTPS

---

## Project Structure

```
lib/
├── main.dart
├── firebase_options.dart
├── screens/
│   ├── login_screen.dart
│   ├── dashboard_screen.dart
│   ├── devices_screen.dart
│   ├── history_screen.dart
│   ├── qr_scanner_screen.dart
│   ├── settings_screen.dart
│   └── about_screen.dart
└── services/
    ├── background_service.dart
    └── notification_service.dart
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Developer

Built by **Bhoomika Jalandhra** during internship at **Muonix Electrosystems LLP**

---

*© 2025 Muonix Electrosystems LLP. All rights reserved.*
