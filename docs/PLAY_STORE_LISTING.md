# Google Play Store Listing & Media Assets

Use this document to copy-paste all Play Console **Store Listing** fields and verify required media assets.

---

## 1. Store Listing Copy

- **App Name** (max 30 chars): `HealthKicks`
- **Default Language**: `English (United States)` (or `French (France)` if primary)
- **App Category**: `Health & Fitness`
- **Tags**: `Fitness`, `Activity tracking`, `Step counter`

### Short Description (max 80 chars — 77 chars)
```text
Connected footwear companion: step tracking, activity insights & fall alerts.
```

### Full Description (max 4,000 chars)
```text
HealthKicks is your companion app for HealthKicks connected footwear, bringing real-time biomechanical activity tracking, step insights, and emergency fall-alert protection to your smartphone.

KEY FEATURES
• Secure BLE Footwear Pairing: Connect to your HealthKicks shoe clip via encrypted Bluetooth Low Energy (LESC) with numeric comparison pairing.
• Live Activity & Step Tracking: Monitor daily step counts, cadence, and activity classifications (walking, running, stairs, resting) in real time and offline.
• Google Health Connect Sync: Optionally synchronize daily step counts with Google Health Connect (READ_STEPS / WRITE_STEPS) to keep your fitness history unified.
• Emergency Fall Alerts: When a fall is detected and confirmed, HealthKicks notifies your configured emergency contacts via email and SMS with optional GPS coordinates so help can reach you faster.
• Privacy-First & GDPR Compliant: Data is hosted in the EU (eu-west-1) with end-to-end TLS encryption and one-tap in-app data export or permanent account deletion.

IMPORTANT WELLNESS DISCLAIMER
HealthKicks is a physical activity and wellness monitoring companion. It is not a certified medical device and is not intended to diagnose, treat, cure, or prevent any disease or medical condition. Emergency fall alerts are best-effort notifications and do not replace emergency services.
```

### Contact & Legal URLs
- **Privacy Policy URL**: `https://app.healthkicks.eu/privacy`
- **Account Deletion URL**: `https://app.healthkicks.eu/privacy#account-deletion`
- **Website**: `https://app.healthkicks.eu`
- **Support Email**: `support@healthkicks.eu` (or your active contact email)

---

## 2. Graphic Assets

| Asset | Requirement | Location |
| :--- | :--- | :--- |
| **App Icon** | `512 × 512 px` PNG | `assets/icon/app_icon.png` (verified `512×512`) |
| **Feature Graphic** | `1024 × 500 px` PNG/JPEG | `docs/play_store_assets/feature_graphic.png` |
| **Phone Screenshots** | ≥ 2 screenshots (16:9 or 9:16, 320–3840 px) | Capture on your Android device (see checklist below) |

### Phone Screenshots Checklist (Capture 3–5 screens)
1. **Dashboard**: Connected shoe status, battery %, live activity badge, and daily step ring.
2. **BLE Pairing / Devices**: Scanning and paired HealthKicks footwear screen.
3. **Activity & Steps**: Daily/hourly step history + Health Connect sync toggle.
4. **Fall Alerts & Emergency Contacts**: Configured contacts + safety alert settings.

---

## 3. Foreground Service Demo Video (15–30 seconds)
Google Play requires a short screen recording for `FOREGROUND_SERVICE_CONNECTED_DEVICE` and `FOREGROUND_SERVICE_DATA_SYNC`:
1. Start screen recording on your Android phone.
2. Open **HealthKicks**, enable **Active Surveillance / BLE Monitoring**, and connect to your footwear (or show the persistent foreground notification).
3. Pull down the **Android Notification Shade** clearly showing the persistent HealthKicks foreground service notification (*"Monitoring connected footwear / syncing telemetry"*).
4. Return to the app to show live step/status updates continuing in the background.
5. Keep the video under **30 seconds** (`.mp4` or unlisted YouTube link for Play Console).
