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
   - Download `google-services.json` from Firebase console
   - Place it in `android/app/`
   - Download `GoogleService-Info.plist` for iOS and place it in `ios/Runner/`

4. Run the app
   ```bash
   flutter run
   ```

---

## Security

- `google-services.json` and `GoogleService-Info.plist` are excluded from this repository
- Firebase rules are configured to allow only authenticated users
- All data is transmitted securely over HTTPS

---

## Privacy Policy

[View Privacy Policy](https://muonix-official.github.io/muonix-env-monitor/privacy-policy.html)

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

## About Muonix

**Muonix Electrosystems LLP**
A-5, Agra Rd, Sethi Colony, Jaipur, Rajasthan 302003
📞 +91 92160 60505
🌐 [muonix.co.in](http://muonix.co.in)
📧 manishmuonix@gmail.com

[![Facebook](https://img.shields.io/badge/Facebook-1877F2?style=flat&logo=facebook&logoColor=white)](https://www.facebook.com/people/Muonix-Electrosystems-Jaipur/61582457949982/)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=flat&logo=linkedin&logoColor=white)](https://in.linkedin.com/company/muonix-electrosystems)
[![Instagram](https://img.shields.io/badge/Instagram-E4405F?style=flat&logo=instagram&logoColor=white)](https://www.instagram.com/muonixelectrosystems/)
[![YouTube](https://img.shields.io/badge/YouTube-FF0000?style=flat&logo=youtube&logoColor=white)](https://www.youtube.com/@MuonixElectrosystems/shorts)

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

*Built by Bhoomika Jalandhra during internship at Muonix Electrosystems LLP*
