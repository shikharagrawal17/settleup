# Bharat Dues: Project Architecture & Status

This document provides a distilled overview of the current system state, design decisions, and architectural implementation as of the production-grade rebranding.

## 核心 (Core) Architecture
- **Tech Stack**: Flutter + Firebase (Firestore/Auth/Messaging).
- **Multi-Platform Support**: Optimized for **Android**, **iOS**, **macOS**, and **Web**.
- **Financial Precision**: Migrated to a **double-precision** system supporting 2-decimal currency values with cent-based rounding for consistent splitting.
- **Authentication & Identity**: 
  - **Google Login**: Primary OAuth-based sign-in (Cross-platform GSI integration).
  - **Identity Linking**: Automatic mapping of legacy member IDs to registered user UIDs via specialized `registries` collection.
  - **Phone Discovery**: Real-time group visibility for invited members via phone number normalization and indexing.
- **Data Model (Firestore)**:
  - `groups/{groupId}`: Main document containing members array, accounting metadata, and `memberIdentifiers`.
  - `groups/{groupId}/expenses`: Collection of shared expense records with granular share-breakdowns.
  - `groups/{groupId}/activities`: Detailed audit trail documenting every modification (e.g., "description changed", "amount from ₹10 to ₹20").
  - `groups/{groupId}/settlements`: Two-way confirmation payment records (Pending vs Confirmed).
  - `users/{uid}`: Private user profile containing PII (email, settings).
  - `publicUsers/{uid}`: Minimal public details (displayName, photoUrl, upiId) for global member resolution.
  - `registries/{key}`: Registry for mapping `phone_+91...` or `email_...` to `uid` for instant member discovery.

## 🛠️ Key Features
1. **Premium Fintech UI**: Immersive dark-mode design with warm amber accents, glassmorphic surfaces, and responsive sheet-based interactions.
2. **Real-Time Sync**: Firestore-backed streams ensuring all members see updates (expenses, settlements, and member edits) instantly.
3. **Simplified Settlement**: Greedy debt-minimization algorithm reduces transfers across complex group topologies.
4. **Smart Expense Logic**: 
   - **Split Modes**: Supports Equal, Percentage, Shares (Multiplier), and Exact Amount modalities.
   - **Rounding Safety**: Cent-based truncation/distribution ensures `Total == sum(Shares)` within ₹0.01 tolerance.
5. **UPI Automation**: Integrated intent deep-linking (`upi://pay`) for seamless payments without leaving the context.
6. **Activity Auditing**: Automatic logging of all structural changes with "before/after" metadata in the activities feed.

## 🛡️ Security & Integrity
- **Membership Guard**: Firestore Rules ensure data isolation, restricting reads/writes to members listed in `memberIdentifiers`.
- **Soft Deletes**: `isDeleted` flags on groups and expenses ensure data recoverability.
- **Precision Validation**: Epsilon-based equality checks (`(a-b).abs() < 0.01`) enforced in both Dart logic and UI layers.

## 📂 Architecture Map
- `lib/providers/app_state.dart`: Centralized Single Source of Truth; handles complex Firestore transactions and identity-linking logic.
- `lib/utils/settlement_helper.dart`: The core financial engine and greedy debt-minimizer.
- `lib/utils/upi_helper.dart`: Cross-platform UPI intent generator and sharing message builder.
- `lib/screens/group_settlement_screen.dart`: Primary group hub with immersive sheets for analytics, balances, and settlements.
- `lib/main.dart`: Global theme definition (`BharatDuesApp`) and platform-specific initialization.

## 🚀 Status
- **Android/Web**: Fully configured and verified with GSI.
- **iOS/macOS**: `Info.plist` and `GoogleService-Info.plist` configured for OAuth and URL schemas.
- **Finance**: 100% migrated to double precision with cent-based rounding logic.
