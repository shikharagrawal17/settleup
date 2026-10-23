# 💸 Bharat Dues

**Bharat Dues** is a premium, real-time shared-ledger application for multi-platform (Android, iOS, Web, macOS) expense tracking. Built for the **GDG DevFest Open Source Edition**, it combines **Google Open Source technologies (Flutter + Firebase)** with **Google Gemini 3.5 Flash** for intelligent multimodal receipt scanning and natural language expense parsing.

![Visual Excellence](https://img.shields.io/badge/UI%2FUX-Premium-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?style=for-the-badge&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase)
![Google Gemini](https://img.shields.io/badge/Google%20AI-Gemini%203.5%20Flash-4285F4?style=for-the-badge&logo=google)

---

## ✨ Key Features

### 🤖 Google Gemini AI Superpowers (DevFest Edition)
*   **✨ Smart AI Split**: Natural-language expense parser powered by **Gemini 3.5 Flash**. Type or speak: *"Aman paid ₹1800 for team pizza with Shikhar and Priya, split equally"*, and Gemini auto-populates the payer, participants, expense category, and exact shares.
*   **📸 Multimodal Smart Receipt Scanner**: Point camera or upload a bill image. Gemini 3.5 Flash extracts the merchant name, total payable amount, line items, and taxes with sub-second latency across Web, Android, iOS, and macOS.
*   **🔑 Google AI Studio Integration**: Built-in API key manager with direct 1-click access to Google AI Studio and secure local storage via `SharedPreferences`.

### 🔐 Modern Authentication & Identity
*   **Google Identity & One-Tap**: Instant cross-platform sign-in using Google Identity Services with seamless web popup auth.
*   **Phone-First Identity**: Members are discovered via normalized phone numbers (`+91...`), ensuring stable linking even before they register.
*   **Deep-Link Invitation Support**: Production-ready join links (`https://bharat-dues.web.app/#/?join=...`) working across Android, iOS, and Web.
*   **Unified Friend Discovery**: Aggregates balances across all groups by unique identifiers (UID/Phone), correctly handling users with identical names.

### 🧠 Financial Precision
*   **Double-Precision Engine**: 100% migrated to `double` types for all currency fields, supporting 2-decimal precision (e.g., ₹10.50).
*   **Epsilon Validation**: Uses intelligent equality checks (`(a-b).abs() < 0.01`) to ensure group balances always match exactly, even with complex splits.
*   **Professional Terminology**: Standardized labels ("Owes" and "Is owed") with consistent color-coding (Red for debt, Green for credit) across the dashboard and group ledgers.
*   **Greedy Debt Simplification**: Minimizes the total number of transfers needed between group members using optimized graph algorithms.

### 🚀 Unified Settlement Flow
*   **Confirm & Record**: High-trust settlement lifecycle.
    *   **Inbound**: Confirm or Dispute payments received from others.
    *   **Outbound**: Track pending payments you've sent.
    *   **WhatsApp Notification**: Immediately notify receivers via WhatsApp after recording a payment, prompting them for a "handshake" confirmation.
*   **Global Netting Logic**: Recording a global receipt automatically "handshakes" (confirms) all underlying group-level debts for that friend.
*   **Bidirectional UPI**:
    *   **Pay Out**: Launches UPI apps (GPay, PhonePe, Paytm, etc.) directly.
    *   **Receive In**: Generates a dynamic UPI QR code for the exact settlement amount.
*   **WhatsApp Reminders**: One-tap sharing of professional, pre-formatted payment reminders with friend-specific details.

### 🏠 Global Dashboard (Home)
*   **Unified Friends Tab**: Command hub for cross-group settlements. Settle net dues or send payment reminders in one click.
*   **Interactive Activity Tab**: Real-time trail of group events and financial actions. Includes inline "Confirm Receipt" buttons for pending payments.
*   **Identity Resilience**: Seamless access and verification logic that works across registered UIDs and manual phone/email identifiers.

---

## 🛠️ Tech Stack
- **Framework**: [Flutter](https://flutter.dev) (v3.35+ / Dart 3.9+)
- **AI Core**: [Google Generative AI SDK](https://pub.dev/packages/google_generative_ai) (`gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-3.8-flash`)
- **Backend & Auth**: Firebase Firestore & Firebase Auth
- **State**: Provider (Centralized `AppState` with Real-time Streams)
- **Local Storage**: `SharedPreferences`

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>= 3.3.0)
- Android Studio / Xcode / Chrome

### Quick Run
```bash
# Clone and enter repo
git clone https://github.com/shikharagrawal17/settleup.git
cd settleup

# Install dependencies
flutter pub get

# Run on Chrome
flutter run -d chrome --web-port=8080

# Run on Android
flutter run -d android
```

### Build Production APK
```bash
flutter build apk --release
```
The compiled APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.
