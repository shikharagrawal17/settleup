# 💸 SettleUp Lite

**SettleUp Lite** is a premium, real-time shared-ledger application inspired by Splitwise, but with a deep focus on **UPI-first settlements** and a modern, high-performance aesthetic. Built with Flutter and Firebase, it transforms how you manage shared expenses with friends, roommates, and travel buddies.

![Visual Excellence](https://img.shields.io/badge/UI%2FUX-Premium-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-v3.0+-02569B?style=for-the-badge&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase)

---

## ✨ Key Features

### 🚀 Real-Time Shared Ledger
Unlike local-only apps, SettleUp Lite uses a **Shared-to-Cloud architecture**. Every group exists as a synchronized document in Firestore.
*   **Instant Sync**: Any expense added is instantly visible to all group members.
*   **Balance Engine**: High-speed calculation of net balances across multiple expenses and settlements.

### 💳 Deep UPI Integration
Designed for the Indian market, making settlements friction-free.
*   **One-Tap "Pay Now"**: Automatically generates a UPI payment link (`upi://pay`) and launches your preferred payment app (GPay, PhonePe, Paytm).
*   **Auto-Record Persistence**: Optionally re-confirm and auto-record a settlement once the UPI intent is launched.
*   **QR Generator**: Each transaction generates a dynamic QR code for easy scanning.

### 📱 iOS & Android Ready
Fully configured for a cross-platform experience:
*   **iOS Support**: Pre-configured `LSApplicationQueriesSchemes` for deep-linking into UPI and WhatsApp apps on iPhone.
*   **Android Optimized**: Smooth performance with Vulkan/Impeller rendering.

### 🛡️ Smart Deletion & Recovery
*   **Soft Delete**: Groups are "archived" rather than erased, allowing for a 4-second **Undo** window on the dashboard.
*   **Group Accountability**: Any member can correct mistakes (delete events) with a confirmation safeguard to ensure ledger integrity.

---

## 🎨 Design Philosophy

We believe financial tools shouldn't be boring. SettleUp Lite features:
*   **Glassmorphism Effects**: Translucent surfaces and vibrant gradients.
*   **MetricPills**: Compact, data-rich pills for total expenditures.
*   **Draggable Sheets**: Fluid interactions for settling up and viewing detailed balances.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev)
- **Database**: [Google Cloud Firestore](https://firebase.google.com/docs/firestore) (Shared-Ledger Model)
- **Auth**: [Firebase Authentication](https://firebase.google.com/docs/auth)
- **Styling**: Vanilla CSS-inspired Flutter UI with custom Design Tokens.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (v3.0+)
- Firebase Project setup

### Configuration
1.  **Firebase**: Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) to the respective platform folders.
2.  **UPI Setup**: Ensure every user adds their UPI ID in the **Edit Profile** section to enable the "Pay Now" feature for others.

### Installation
```bash
# Clone the repository
git clone https://github.com/shikharagrawal17/settleup.git

# Install dependencies
flutter pub get

# Run the app
flutter run
```

---

## 🤝 Contributing
Mistakes happen—that's why anyone in the group can edit! If you find a bug or want to suggest a feature, feel free to open a PR.

---

## 📄 License
This project is for educational and personal use. Feel free to fork and build your own version!
