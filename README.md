# 💸 SettleUp Lite

**SettleUp Lite** is a premium, real-time shared-ledger application inspired by Splitwise, but with a deep focus on **UPI-first settlements** and a modern, high-performance aesthetic. Built with Flutter and Firebase, it transforms how you manage shared expenses with friends, roommates, and travel buddies.

![Visual Excellence](https://img.shields.io/badge/UI%2FUX-Premium-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-v3.0+-02569B?style=for-the-badge&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase)

---

## ✨ Key Features

### 🔐 Dual-Authentication
*   **Google One-Tap**: Instant sign-in with your Google account.
*   **Phone OTP Login**: Use your mobile number with verified SMS codes for a more accessible onboarding experience.

### 🧠 Intelligence & Optimization
*   **Simplify Debts**: Uses a greedy algorithm to minimize the total number of transfers needed between group members.
*   **Smart Analytics**: Real-time bar-chart visualization of spending by category (Food, Travel, Rent, etc.).
*   **Auto-Categorization**: Intelligently detects and suggests categories based on expense descriptions.

### 🚀 Real-Time Shared Ledger
Unlike local-only apps, SettleUp Lite uses a **Shared-to-Cloud architecture**. Every group exists as a synchronized document in Firestore.
*   **Instant Sync**: Any expense added is instantly visible to all group members.
*   **Balance Engine**: High-speed calculation of net balances across multiple expenses and settlements.

### 💳 Deep UPI Integration
Designed for the Indian market, making settlements friction-free.
*   **One-Tap "Pay Now"**: Automatically generates a UPI payment link and launches apps like GPay, PhonePe, or Paytm.
*   **Two-Way Confirmation**: Payments are recorded as `pending` and only update balances once the receiver confirms receipt.
*   **QR Generator**: Each transaction generates a dynamic QR code for easy scanning.

### 🛡️ Production & Stability
*   **Hardened Modal UI**: Completely overhauled the Add/Edit Expense modal with a zero-overflow vertical-stack architecture, ensuring perfect responsiveness down to 280px.
*   **Stability & Reliability**: Resolved critical Material 3 rendering crashes (infinite width constraints) and implemented null-safe logic for evolving group member lists.
*   **Financial Precision**: Hardened split calculations for Percentage and Share modes with intelligent rounding to ensure group balances always sum correctly.
*   **Profile Guard**: Mandatory onboarding for missing Firestore records to ensure data integrity across all screens.
*   **Democratic Governance**: Shared group management where any member can contribute; ownership is fluid with automatic succession.
*   **Balance Locks**: Structural safety prevents member removal or group closure until all balances are exactly ₹0.
*   **Push Notifications**: Integrated FCM infrastructure for real-time activity and payment verification alerts.

---

## 🎨 Design Philosophy
We believe financial tools shouldn't be boring. SettleUp Lite features:
*   **Glassmorphism Effects**: Translucent surfaces and vibrant gradients.
*   **MetricPills**: Compact, data-rich pills for total expenditures.
*   **Draggable Sheets**: Fluid interactions for settling up and viewing detailed balances.

---

## 🛠️ Tech Stack
- **Framework**: [Flutter](https://flutter.dev)
- **Database**: Firestore (Shared-Ledger Model)
- **Auth**: Firebase Authentication (Google + Phone OTP)
- **Notifications**: Firebase Cloud Messaging
- **Logic**: Provider-based State Management

---

## 🚀 Getting Started

### Configuration
1.  **Firebase**: Add your `google-services.json` and `GoogleService-Info.plist`.
2.  **Auth Setup**: Enable Google and Phone login providers in your Firebase Console.
3.  **Cloud Functions**: Deploy the provided `FIREBASE_NOTIFICATIONS_LOGIC` to enable push alerts.
4.  **UPI Setup**: Ensure every user adds their UPI ID in the profile section.

### Installation
```bash
flutter pub get
flutter run
```

---

## 📄 License
This project is for educational and personal use. Feel free to fork and build your own version!
