# Bharat Dues: Project Architecture & Status

This document provides a distilled overview of the system state, design decisions, and architectural implementation for **Bharat Dues**.

## 核心 (Core) Architecture
- **Tech Stack**: Flutter + Firebase (Firestore/Auth/Messaging).
- **Multi-Platform Support**: Optimized for **Android**, **iOS**, and **Web (Wasm/PWA)**.
- **Financial Precision**: Uses a **double-precision** system with **Epsilon Validation** (`< 0.01`) for consistent multi-member splitting and settlement tracking.
- **Authentication & Identity**: 
  - **Google Login**: Primary OAuth-based sign-in.
  - **Identity Linking**: Automatic mapping of legacy manual IDs to registered UIDs.
  - **Phone-First Discovery**: Real-time group visibility for invited members via phone number normalization and indexing in the `registries` collection.
- **Data Model (Firestore)**:
  - `groups/{groupId}`: Shared-ledger document with members, analytics, and activity trails.
  - `groups/{groupId}/settlements`: High-trust payment records (Pending -> Confirmed/Disputed).
  - `registries/{phoneKey}`: Lookup for mapping invitation phone numbers to active UIDs.

## 🛠️ Key Features & Logic
1. **Premium Fintech UI**: High-performance Light Theme with glassmorphic surfaces and vibrant blue accents (`#00B9F1`).
2. **Cross-Platform Join Links**: Implements a robust invitation system using production-grade join URLs (`https://bharat-dues.web.app/#/?join=...`) to onboard members onto existing groups.
3. **Unified Financial Dashboard**:
   - **Friends Tab**: Aggregates net balances across all groups.
   - **Terminology Audit**: Standardized UI copy using "Owes" and "Is owed" for better financial clarity.
   - **Global Netting Architecture**: Recording a global receipt automatically confirms all underlying group-level transactions, significantly reducing UI noise and "pending" notifications.
3. **Advanced Settlement Engine**:
   - **Handshake Lifecycle**: Every global settlement requires mutual agreement.
   - **Bidirectional UPI**: Integrated deep-linking and dynamic QR generation for inbound and outbound payments.
   - **WhatsApp Automation**: Formatted sharing of payment requests and reminders with friend-specific balance details.
4. **Precision Expense Logic**: 
   - **Split Modes**: Equal, Percentage, Shares, and Exact Amount.
   - **Cent-Based Rounding**: Ensures `Total == sum(Shares)` within ₹0.01 tolerance across any number of members.

## 🛡️ Security & Integrity
- **Membership Isolation**: Firestore Rules restrict data access based on the `memberIdentifiers` array.
- **Soft Deletes**: Group and expense deletion with full state restoration.
- **Identity Integrity**: Friends are distinguished by UID or Normalized Phone, preventing balance merging for users with identical names.

## 📂 Architecture Map
- `lib/providers/app_state.dart`: Single Source of Truth; handles Firestore transactions and identity-linking.
- `lib/screens/home_screen.dart`: Global Financial Dashboard and Activity trails.
- `lib/utils/settlement_helper.dart`: The mathematical core for debt simplification.
- `lib/utils/upi_helper.dart`: Standardized UPI intent generator.

## 🚀 Status
- **Web/PWA**: Fully deployed at [bharat-dues.web.app](https://bharat-dues.web.app) with optimized assets and manifest.
- **Android**: Verified with `com.example.bharat_dues` package and multi-app `<queries>` for deep-linking.
- **iOS**: Configured with `com.example.bharatDues` bundle and signed with high-trust URL schemes.
- **Production-Ready**: Identity-aware, precision-safe, and rebranded with a unified logo and design language.
