# Juspay HyperCheckout SDK — Flutter Integration Tester

A developer testing app for end-to-end validation of the Juspay HyperCheckout
Flutter SDK integration. Covers all three SDK lifecycle steps with a built-in
request/response log viewer.

---

## Features

| Step | Action | Description |
|------|--------|-------------|
| 01 | **Initiate SDK** | Boots up the Hyper engine with a configurable JSON payload |
| 02 | **Session API** | Calls `/session` from the app, extracts `sdk_payload` automatically |
| 03 | **Process Payment** | Calls `hyperSDK.process()` with the extracted `sdk_payload` |
| — | **Log Viewer** | Filterable real-time log panel for all requests, responses, callbacks |

---

## Quick Start

### 1. Prerequisites

- Flutter ≥ 3.0.0
- `clientId` and `hyperSDKVersion` from the Juspay team
- `apiKey` for the `/session` endpoint (from Juspay dashboard)

### 2. Configure `clientId`

**Android** — `android/build.gradle`:
```groovy
ext {
    clientId        = "YOUR_CLIENT_ID"       // ← replace
    hyperSDKVersion = "2.1.7"               // ← replace
}
```

**Android** — `android/app/MerchantConfig.txt`:
```
clientId = YOUR_CLIENT_ID
```

**iOS** — `ios/MerchantConfig.txt`:
```
clientId = YOUR_CLIENT_ID
```

### 3. Run

```bash
flutter pub get
flutter run
```

```
By default, when you open the app, the asset loaded in the Payment Page (PP) will be from msprod.

To load the PP with your own testing client ID, follow these steps:

1. Open the app.
2. Initiate the flow using your respective client ID.
3. Trigger a process call with the same client ID.
        - At this point, the PP will still open with the msprod UI.
4. Kill the app completely.
5. Reopen the app.
6. Initiate again using the same client ID as in Step 2.
7. Trigger a process call.
        - Now, the PP will load with the UI corresponding to your client ID.
```

---

## Integration Flow

```
┌─────────────────────────────────────────┐
│  Step 1 — Initiate SDK                  │
│  hyperSDK.initiate(payload, callback)   │
│  → initiateCallback: initiate_result    │
└────────────────┬────────────────────────┘
                 │ SDK Ready
┌────────────────▼────────────────────────┐
│  Step 2 — Session API (your backend)    │
│  POST /session  →  { sdk_payload, ... } │
│  sdk_payload auto-fills Step 3          │
└────────────────┬────────────────────────┘
                 │ sdk_payload extracted
┌────────────────▼────────────────────────┐
│  Step 3 — Process                       │
│  hyperSDK.process(sdk_payload, cb)      │
│  → processCallback: process_result      │
│    status: charged | backpressed | ...  │
└─────────────────────────────────────────┘
```

---

## Session API

> **Security Note**: In production, the `/session` call MUST originate from
> your backend server, never from the mobile app directly. This app makes the
> call client-side for **testing purposes only**.

Default URL: `https://api.juspay.in/session`  
Auth: `Authorization: Basic base64(apiKey:)`

Minimum required payload fields:
```json
{
  "order_id": "unique_order_id",
  "amount": 1000,
  "currency": "INR",
  "customer_id": "cust_001",
  "customer_email": "user@example.com",
  "customer_phone": "9999999999",
  "payment_page_client_id": "YOUR_CLIENT_ID",
  "action": "paymentPage",
  "return_url": "https://your-app.com/callback"
}
```

The response `sdk_payload` field is automatically extracted and pre-filled
into Step 3's process payload input.

---

## Android Setup Notes

Your `MainActivity` **must** extend `FlutterFragmentActivity`:
```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

---

## Log Panel

The **LOGS** tab shows a chronological reverse-sorted list of all events:

| Tag | Color | Meaning |
|-----|-------|---------|
| `▲ REQ` | Blue | Outgoing request / SDK call payload |
| `▼ RES` | Green | Incoming response |
| `✓ OK` | Bright Green | Success (e.g. charged, initiate success) |
| `✕ ERR` | Red | Error or failure |
| `● INFO` | Amber | Informational SDK callbacks |

Tap any log entry to expand it. Tap the copy icon to copy the body.
Use the filter chips (`ALL / REQ / RES / OK / ERR / INFO`) to narrow the view.

---

## Project Structure

```
lib/
├── main.dart
├── models/
│   └── log_entry.dart       # LogEntry model + LogType enum
├── screens/
│   └── home_screen.dart     # Main UI: 3-step integration + log tab
└── widgets/
    ├── step_card.dart        # StepCard + SdkActionButton
    ├── json_input_field.dart # JSON editor with live validation + format
    └── log_panel.dart        # Filterable log viewer
```

---

## Dependencies

```yaml
hypersdkflutter: ^4.0.35
http: ^1.2.0
intl: ^0.19.0
```