# Google Play Console — Sensitive Permissions & Declarations

This document maps every sensitive permission in [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) to its code usage and the required Google Play Console declaration.

## 1. Permissions Summary

| Permission | Code Usage | Play Console Action |
| :--- | :--- | :--- |
| `SEND_SMS` | `MainActivity.kt` (`SmsManager`), `FallSmsSender` | Submit **SMS/Call Log Permissions Declaration** — select **Physical safety / emergency alerts** (automated emergency SMS sent to user-configured contacts when a fall alert is confirmed). |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | `MainActivity.kt` (`LocationManager`), `DefaultFallLocationProvider` | Declare in **Data Safety** as **Optional** precise/approximate location collected only when an emergency fall alert is triggered. (`BLUETOOTH_SCAN` uses `neverForLocation`.) |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | `ForegroundService` (`flutter_foreground_task`) | Declare in **App Content → Foreground service permissions** (`connectedDevice` for continuous BLE GATT monitoring of HealthKicks footwear). Attach a short screen-recording video showing the persistent notification. |
| `FOREGROUND_SERVICE_DATA_SYNC` | `ForegroundService` (`flutter_foreground_task`) | Declare in **App Content → Foreground service permissions** (`dataSync` for offline step/telemetry sync to AWS IoT Core / REST API). |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Background fall-alert surveillance | Justify in Play Console as required for uninterrupted real-time fall-detection monitoring. |
| `health.READ_STEPS` / `health.WRITE_STEPS` | `health` plugin (Health Connect) | Complete **Health Connect App Declaration** and ensure the Privacy Policy (`https://app.healthkicks.eu/privacy`) discloses Health Connect step read/write usage. |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | `flutter_blue_plus` (BLE GATT client) | Standard runtime permissions (no special Play Console form; `BLUETOOTH_ADVERTISE` removed as unused). |

## 2. Store Listing & Compliance Reminders
- **Privacy Policy URL**: `https://app.healthkicks.eu/privacy`
- **Account Deletion URL**: Ensure a public web URL with account-deletion instructions/flow is linked in the Play Console **Data Safety** form (in addition to the in-app deletion flow).
- **Medical Disclaimer**: In the **Health Apps** declaration and store description, state clearly that HealthKicks is a wellness/activity companion and not a certified medical device.
