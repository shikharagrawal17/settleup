# 💸 Bharat Dues

**Bharat Dues** is a premium, real-time shared-ledger application for multi-platform (Android, iOS, Web, macOS) expense tracking. Inspired by the best fintech tools, it focuses on **UPI-first settlements**, **high-precision financial logic**, and a modern, high-performance aesthetic.

![Visual Excellence](https://img.shields.io/badge/UI%2FUX-Premium-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?style=for-the-badge&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase)

---

## ✨ Key Features

### 🔐 Modern Authentication & Identity
*   **Google One-Tap**: Instant cross-platform sign-in using Google Identity Services.
*   **Phone-First Identity**: Members are discovered via normalized phone numbers (`+91...`), ensuring stable linking even before they register.
*   **Deep-Link Invitation Support**: Production-ready join links (`https://bharat-dues.web.app/#/?join=...`) that work across Android, iOS, and Web.
*   **Unified Friend Discovery**: Aggregates balances across all groups by unique identifiers (UID/Phone), correctly handling users with identical names.

### 🧠 Financial Precision
*   **Double-Precision Engine**: 100% migrated to `double` types for all currency fields, supporting 2-decimal precision (e.g., ₹10.50).
*   **Epsilon Validation**: Uses intelligent equality checks (`(a-b).abs() < 0.01`) to ensure group balances always match exactly, even with complex splits.
*   **Professional Terminology**: Standardized labels ("Owes" and "Is owed") with consistent color-coding (Red for debt, Green for credit) across the dashboard and group ledgers.
*   **Greedy Debt Simplification**: Minimizes the total number of transfers needed between group members using optimized algorithms.

### 🚀 Unified Settlement Flow
*   **Confirm & Record**: A high-trust settlement lifecycle. 
    *   **Inbound**: Confirm or Dispute payments received from others.
    *   **Outbound**: Track pending payments you've sent.
    *   **WhatsApp Notification**: Immediately notify receivers via WhatsApp after recording a payment, prompting them for a "handshake" confirmation.
*   **Global Netting Logic**: Recording a global receipt automatically "handshakes" (confirms) all underlying group-level debts for that friend, eliminating redundant notifications.
*   **Bidirectional UPI**:
    *   **Pay Out**: Launches UPI apps (GPay, PhonePe, Paytm, etc.) directly.
    *   **Receive In**: Generates a dynamic UPI QR code for the exact settlement amount.
*   **WhatsApp Reminders**: One-tap sharing of professional, pre-formatted payment reminders with friend-specific details.

### 🏠 Global Dashboard (Home)
*   **Unified Friends Tab**: Command hub for cross-group settlements. Remind friends or settle your total net dues in one shot.
*   **Interactive Activity Tab**: Real-time trail of group events and financial actions. Includes inline "Confirm Receipt" buttons for pending payments, unified across all your shared activities.
*   **Identity Resilience**: Seamless access and verification logic that works across registered UIDs and manual phone/email identifiers.

### 🌐 Web & PWA Optimization
*   **Add to Home Screen**: High-quality PWA support with optimized manifest and icons.
*   **Wasm Performance**: Targeted WebAssembly builds for near-native scroll performance on modern browsers.

---

## 🛠️ Tech Stack
- **Framework**: [Flutter](https://flutter.dev) (v3.22+)
- **Backend**: Firebase Firestore (Shared-Ledger Model)
- **State**: Provider (Centralized `AppState` with Real-time Streams)
- **Icons**: Generated via `flutter_launcher_icons` using the Bharat Dues design system.

---

## 🚀 Platform Configuration (Critical)

### Android (API 30+)
To support UPI and WhatsApp launching, the `AndroidManifest.xml` includes `<queries>` for:
- `upi` scheme
- `whatsapp` scheme & packages (`com.whatsapp`, `com.whatsapp.w4b`)
- `https` scheme for LinkedIn/External links

### iOS
`Info.plist` declares `LSApplicationQueriesSchemes` for:
- `upi`, `phonepe`, `gpay`, `paytm`, `bhim`
- `whatsapp`

*Note: iOS Simulator does not support UPI/WhatsApp launching; use a physical device for full testing.*

---

## 📂 Project Structure
- `lib/providers/app_state.dart`: Core logic (Financials, Firestore Sync, Identity Linking).
- `lib/screens/home_screen.dart`: The Global Dashboard and Friend Hub.
- `lib/screens/group_settlement_screen.dart`: The immersive group-level ledger.
- `widgets/app_shell_widgets.dart`: Premium design system tokens and surfaces.

---

## 📄 License
This project is for educational and personal use. Bharat Dues.
