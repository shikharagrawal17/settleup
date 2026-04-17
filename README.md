# 💸 Bharat Dues

**Bharat Dues** is a premium, real-time shared-ledger application for multi-platform (Android, iOS, Web, macOS) expense tracking. Inspired by the best fintech tools, it focuses on **UPI-first settlements**, **high-precision financial logic**, and a modern, high-performance aesthetic.

![Visual Excellence](https://img.shields.io/badge/UI%2FUX-Premium-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?style=for-the-badge&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase)

---

## ✨ Key Features

### 🔐 Modern Authentication
*   **Google One-Tap**: Instant cross-platform sign-in using Google Identity Services (optimized for Web and Mobile).
*   **Phone Discovery**: Invited members automatically see their groups upon first sign-in via phone number matching.
*   **Persistent Sessions**: Securely links anonymous invites to registered accounts via `registries` and `publicUsers` lookup.

### 🧠 Financial Precision
*   **Double-Precision Engine**: 100% migrated to `double` types for all currency fields, supporting 2-decimal precision (e.g., ₹10.50).
*   **Epsilon Validation**: Uses intelligent equality checks (`(a-b).abs() < 0.01`) to ensure group balances always match exactly, even with complex splits.
*   **Flexible Splitting**: Supports Equal, Percentage, Multiplier-based (shares), and Exact Amount splitting methods.
*   **Simplify Debts**: Greedy algorithms minimize the total number of transfers needed between group members.

### 🚀 Real-Time Shared Ledger
Unlike local-only apps, Bharat Dues uses a **Shared-to-Cloud architecture**.
*   **Instant Sync**: Firestore-backed streams ensure any added expense is visible to all members immediately.
*   **Detailed Activity Logs**: A dedicated `activities` feed tracks exactly what changed (amount, description, category, or members) with "before and after" details.
*   **Soft Deletes**: Safety mechanisms for group and expense deletion with restoration capabilities.

### 💳 Deep UPI Integration
*   **One-Click Pay**: Launches UPI apps (GPay, PhonePe, Paytm, etc.) directly with pre-filled amounts and payee details.
*   **Settlement Share**: Generate formatted WhatsApp summaries with embedded UPI payment links.
*   **Two-Way Handshake**: Balances only clear when the receiver confirms receipt, preventing disputed cash/UPI transfers.

### 🛡️ Production & Stability
*   **Responsive Redesign**: Immersive, safe-area aware modals and glassmorphic UI elements.
*   **Balance Locks**: Structural safety prevents removing members unless their adjusted balance is exactly ₹0.00.
*   **Cross-Platform GSI**: Fully configured for Web (managed GSI client IDs) and iOS (URL schemes and permission strings).

---

## 🛠️ Tech Stack
- **Framework**: [Flutter](https://flutter.dev) (v3.22+)
- **Database**: Firestore (Shared-Ledger Model with Subcollections)
- **Auth**: Firebase Authentication (Google GSI + Phone Identity)
- **State Management**: Provider (Centralized `AppState`)
- **Platform Specifics**: `google_sign_in`, `url_launcher` (UPI), `flutter_contacts`, `share_plus`.

---

## 🚀 Getting Started

### Platform Configuration
1.  **Web**: Add your Google Client ID meta tag to `web/index.html`.
2.  **iOS**: Ensure `GoogleService-Info.plist` is in `ios/Runner` and URL schemes are set in `Info.plist`.
3.  **Android**: Place `google-services.json` in `android/app/`.

### Installation
```bash
# Get dependencies
flutter pub get

# Run on Web
flutter run -d chrome

# Run on Mobile
flutter run -d ios   # or android
```

---

## 📂 Project Structure
- `lib/providers/app_state.dart`: The core logic hub handling all financial transactions, Firestore sync, and identity linking.
- `lib/utils/settlement_helper.dart`: The mathematical engine for debt simplification and rounding-safe splits.
- `lib/utils/upi_helper.dart`: Deep-link generator for standard UPI intent schemas.
- `lib/screens/group_settlement_screen.dart`: The immersive group dashboard and settlement workflow.
- `lib/models/`: Strongly typed data models for Expenses, Activities, Settlements, and Profiles.

---

## 📄 License
This project is for educational and personal use. Bharat Dues.
