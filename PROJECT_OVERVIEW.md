# Bharat Dues: Project Architecture & Status

This document provides a distilled overview of the current system state, design decisions, and architectural implementation as of the production-grade rebranding.

## 核心 (Core) Architecture
- **Tech Stack**: Flutter + Firebase (Firestore/Auth/Messaging).
- **Multi-Platform Support**: Optimized for **Android**, **iOS**, **macOS**, and **Web**.
- **Financial Precision**: Migrated to a **double-precision** system supporting 2-decimal currency values with epsilon-based rounding for perfect balance matching.
- **Authentication**: 
  - **Google Login**: Primary OAuth-based sign-in (Cross-platform GSI integration).
  - **Phone Discovery**: Users see groups they were invited to via phone number immediately upon registration.
- **Data Model**:
  - `groups/{groupId}`: Main document containing members, high-precision `netBalances`, and metadata.
  - `groups/{groupId}/expenses`: Activity log documenting every spend with granular "Changed Fields" auditing.
  - `groups/{groupId}/settlements`: Two-way confirmation payment tracking with UPI integration.
  - `users/{uid}`: Profile with normalized identifiers and FCM tokens.

## 🛠️ Key Features
1. **Premium Fintech UI**: Immersive dark-mode design with glassmorphism, responsive modals, and scrollable confirmation sheets.
2. **Real-Time Sync**: Firestore-backed streams ensure all invited members see updates instantly.
3. **Simplified Settlement**: greedy minimization algorithms reduce group debts to the fewest possible transactions.
4. **Smart Expense Logic**: 
   - Supports fixed amount and percentage-based splitting.
   - Granular Activity Logs showing exactly what changed during an edit (e.g., "amount from ₹10 to ₹20").
5. **UPI Automation**: Deep-linking for instant payments; manual recording for cash settlements.
6. **Robust Data Validation**: Epsilon-based equality checks (`(a-b).abs() < 0.01`) ensure financial integrity across platforms.

## 🛡️ Security & Integrity
- **Membership Guard**: Firestore Rules restrict data access only to active group members.
- **Balance Integrity**: Prevents member removal if their net balance is not exactly ₹0.00.
- **Precision Validation**: All inputs are sanitized for double-precision compatibility.

## 📂 Architecture Map
- `lib/providers/app_state.dart`: Centralized Single Source of Truth; handles all multi-document Firestore transactions.
- `lib/utils/settlement_helper.dart`: The core financial engine and debt-minimization algorithm.
- `lib/utils/upi_helper.dart`: Cross-platform UPI link generator.
- `lib/screens/group_settlement_screen.dart`: The primary dashboard for group activity and financial tracking.
- `lib/main.dart`: Global theme definition (`BharatDuesApp`) and platform-specific initialization.

## 🚀 Status
- **Android/Web**: Fully configured and verified.
- **iOS/macOS**: `Info.plist` and `GoogleService-Info.plist` configured for OAuth and URL schemes.
- **Finance**: 100% migrated from integer to double precision.
