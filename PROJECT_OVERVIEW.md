# SettleUp Lite: Project Architecture & Status

This document provides a distilled overview of the current system state, design decisions, and architectural implementation as of the completion of **Phase 5: Production Hardening & UI Overhaul**.

## 核心 (Core) Architecture
- **Tech Stack**: Flutter + Firebase (Firestore/Auth/Messaging/Functions logic).
- **Dual-Authentication**: 
  - **Google Login**: Primary OAuth-based sign-in.
  - **Phone OTP**: (Experimental/Disabled) Infrastructure ready for number-verified onboarding.
- **Data Model**:
  - `groups/{groupId}`: Main document containing members, net balances, and metadata.
  - `groups/{groupId}/expenses`: Activity log with category auto-persistence.
  - `groups/{groupId}/settlements`: Two-way confirmation payment tracking.
  - `users/{uid}`: Profile with normalized phone, UPI ID, and FCM tokens.

## 🛠️ Key Features
1. **Real-Time Synchronization**: All views use Firestore `snapshots()` for instant group updates.
2. **Simplified Debts (Phase 2)**: Greedy minimization algorithm reduces settlement clutter.
3. **Smart Analytics (Phase 3)**:
   - **Auto-Categories**: NLP-lite detection of expense categories from descriptions with manual override persistence.
   - **Visual Dashboard**: Category-wise bar chart breakdown of group spending.
4. **Push Notifications (Phase 4)**: FCM-ready frontend with server-side logic guide provided.
5. **UPI Automation**: Deep-linking to GPay/PhonePe/Paytm with automated confirmation flow.
6. **Production Hardening (Phase 5)**: 
   - **Responsive Redesign**: Zero-overflow, vertical-stack Expense modal.
   - **Stability Fixes**: Resolved `BoxConstraints` infinite width crashes and `Null check` errors during member-delta operations.
   - **Financial Integrity**: Improved rounding logic for percentage/multiplier splits.

## 🛡️ Security & Integrity
- **Profile Guard**: Automated redirection to onboarding if user document is deleted or missing.
- **Democratic Ownership**: Shared group management with automated leadership succession.
- **Balance Lock**: Prevents data fragmentation by locking member removal until balance is ₹0.
- **Aggregated Performance**: Server-side map of `netBalances` avoids O(N) client-side calculations.

## 🚀 Dev Info
- `_enableFriendsFeature` (@ `lib/screens/home_screen.dart`): Toggles 1-on-1 Friends dashboard.
- `firestore.rules`: Membership-based access control and event-creator deletion locks.
- **Rendering**: Using Impeller (Vulkan) for smooth animations and transitions.

## 📂 Architecture Map
- `lib/providers/app_state.dart`: Centralized logic (Single Source of Truth).
- `lib/utils/settlement_helper.dart`: The core financial engine.
- `lib/screens/app_shell.dart`: The global session & profile guard router.
