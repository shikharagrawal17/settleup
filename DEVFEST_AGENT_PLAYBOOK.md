# 🚀 Road to Devfest: Open Source Edition — Autonomous Agent Playbook
> **Event:** Road to Devfest: Opensource Edition | **Host:** GDG Cloud Bengaluru (@gdgcblr)  
> **Venue:** Google Ananta, Mahadevapura, Bengaluru, 560037  
> **Pillars:** **FORK ➔ BUILD ➔ DOCUMENT ➔ MERGE**  
> **Mission:** Transform any forked open-source repository into an audit-grade, Top-10 winning contribution during a 3-hour build sprint.

---

## 🧭 Executive Summary & Core Mindset

You are an autonomous engineering agent paired with a developer at **Google Ananta, Bengaluru**.
Your objective is to fork, elevate, harden, and submit a maintainer-ready pull request using **Google Open Source & AI Technologies** (Gemma, Gemini AI, Flutter, Firebase Open Source SDKs, Android ADK, TensorFlow).

Maintainers do **not** merge superficial AI wrappers, noisy diffs, or unverified experiments. Maintainers merge code that delivers:
1. **Mathematical Invariant Integrity:** Double-entry consistency, zero ledger drift, zero financial or state loopholes.
2. **Deep Google AI & Open Source Value:** Native Gemini/Gemma integration with structured schemas, high-speed heuristics fallback, and offline resiliency.
3. **World-Class Visual Craftsmanship:** High-contrast, brand-authentic themes (e.g. Bharat Dues / Paytm blue `#002E6E` & `#00B9F1`), zero generic AI slop.
4. **Zero-Lint Quality & Deterministic Tests:** 100% test pass rate with zero warnings on `flutter analyze` or ecosystem linters.
5. **Turnkey Multi-Platform Release:** Live Web preview on Firebase Hosting + installable release Android APK + crystal-clear PR documentation.

---

## ⏱️ 3-Hour Build Sprint Timeline (Google Ananta)

| Time Window | Phase | Primary Deliverables |
|---|---|---|
| **11:00 AM – 11:30 AM** | **Phase 1: Recon & Invariant Audit** | Environment check, codebase scan, domain model audit, identify SSOT & edge-cases |
| **11:30 AM – 12:20 PM** | **Phase 2: Core Engineering & Hardening** | Universal canonical ID resolution, double-entry mathematical invariants, self-healing drift check |
| **12:20 PM – 01:10 PM** | **Phase 3: Google AI & UX Polish** | Gemini/Gemma integration, OCR/category parsing, high-contrast theme, zero-lint test suite |
| **01:10 PM – 01:30 PM** | **Phase 4: Release & PR Submission** | Firebase Hosting deploy, APK build, Mermaid architecture diagrams, PR ready for merge |

---

## ⚡ Step-by-Step Autonomous Execution Guide

### Phase 1: Deep Reconnaissance & Gap Analysis (30 Mins)

1. **Ecosystem & Health Check:**
   - Detect project type (Flutter, TypeScript, Python, Go).
   - Run baseline linter and test suite to capture current errors:
     ```bash
     flutter analyze
     flutter test
     ```
   - Map existing architecture: State management (Provider/Riverpod/Bloc), database models, navigation patterns.

2. **Domain Model & Ledger Audit:**
   - Audit all mutation points (Create, Update, Delete, Settle, Dispute).
   - **Check ID Fragmentation:** Are entities referenced interchangeably by Firebase Auth `uid`, internal doc ID `m.id`, phone number, or display name?
   - **Audit State Disconnects:** Does a detail/sub-screen show one balance while the dashboard/home screen shows another?
   - **Verify Conservation Law:**
     $$\sum_{i=1}^{N} \text{balance}_i \equiv 0.00$$

3. **Identify High-Value Google Open Source Integration:**
   - **Gemini / Gemma:** Structured JSON receipt scanning, smart split ratios, natural language group categorization.
   - **Firebase Open Source SDKs:** Atomic batch operations, real-time snapshot streams, offline persistence.
   - **Flutter Material 3:** Accessible high-contrast typography and authentic design system.

---

### Phase 2: Core Engineering & Invariant Hardening (50 Mins)

1. **Establish Single Source of Truth (SSOT):**
   - The double-entry journal / transactions ledger is the ground truth.
   - Any cached / aggregated projection (e.g. `group.netBalances`, `user.balance`) must derive deterministically from the journal.
   - Implement **Automated Self-Healing**: if cached balances drift from the ledger by $> 0.01$, asynchronously reconcile and heal Firestore in the background.

2. **Implement Universal Canonical ID Resolution:**
   - Guarantee that every member reference maps to a single canonical ID:
     ```dart
     String resolveCanonicalMemberId(String rawId, List<GroupMember> members) {
       // 1. Direct match on member.id
       // 2. Match on member.uid (Firebase Auth)
       // 3. Match on normalized 10-digit phone number
       // 4. Fallback to rawId
     }
     ```
   - Fold all incoming expense shares, payer IDs, and settlement parties through canonical resolution before mutating state.

3. **Pending vs. Confirmed Transaction Isolation:**
   - Unverified transactions must remain strictly in `pending` status.
   - Pending transactions must NEVER alter confirmed ledger balances.
   - Provide direct bilateral actions: **Confirm**, **Dispute**, or **Cancel**.

4. **Reactive State Binding & Navigation Refresh:**
   - Call `notifyListeners()` (or emit state) on every mutation (`add`, `update`, `delete`, `settle`, `confirm`, `reconcile`).
   - Observe state reactively in UI widgets (`context.watch<AppState>()`).
   - Await all navigation pushes and modal sheets, triggering `setState()` upon return.

---

### Phase 3: Google AI Integration & UX Craftsmanship (50 Mins)

1. **Google Gemini / Gemma AI Integration:**
   - Use structured outputs (`responseSchema` or strictly validated JSON).
   - Provide zero-latency local fallback: Fast regex/heuristics execute first; Gemini runs in parallel for deep semantic understanding.
   - Graceful offline handling: If API key is missing or network fails, fallback silently to deterministic local parsing.

2. **Design Standards (Anti-Slop Directive):**
   - **NO generic AI dark-glass gradients** or low-contrast washed-out text.
   - Use high-contrast brand tokens (e.g., `#002E6E` Dark Blue + `#00B9F1` Primary Cyan + pure white cards).
   - Ensure AAA accessibility contrast ratios for figures and badges.
   - Clean typography with Google Fonts (Outfit, Inter, or Roboto).

3. **Automated Financial Invariant Test Suite:**
   - Create a dedicated unit test suite (e.g. `test/financial_audit_test.dart`).
   - Validate:
     - Transaction updated from "Paid by Other" to "Paid by Me".
     - Pending settlement isolation.
     - Multi-variant ID resolution across UID, phone, and doc ID.
     - Conservation invariant $\sum \text{balances} \equiv 0.00$.
   - Verify with:
     ```bash
     flutter test
     flutter analyze
     ```

---

### Phase 4: Production Builds, Documentation & PR Submission (20 Mins)

1. **Multi-Platform Release Packaging:**
   - **Web Release:**
     ```bash
     flutter build web --release
     firebase deploy --only hosting
     ```
   - **Android Release APK:**
     ```bash
     flutter build apk --release
     cp build/app/outputs/flutter-apk/app-release.apk bharat-dues-release.apk
     ```

2. **Maintainer-Ready PR Documentation (`PR_TEMPLATE.md`):**
   - **Title:** `feat(core): audit-grade double-entry engine, canonical ID resolution & Google AI integration`
   - **Body Structure:**
     - 📌 **Problem & Context:** Exact description of data drift, key fragmentation, or missing feature.
     - 🛡️ **Audit-Grade Fixes:** Mathematical invariant proof, canonical ID resolution, double-entry consistency.
     - 🤖 **Google Technologies Utilized:** Gemini / Gemma AI, Flutter cross-platform, Firebase Open Source SDKs.
     - 🧪 **Test Verification:** Test pass logs (`flutter test` 100% pass, `flutter analyze` 0 issues).
     - 🌐 **Live Demo & Artifacts:** Firebase Hosting link + APK artifact.

---

## 📋 Pre-Flight Checklist Before Submitting PR

- [ ] `flutter analyze` runs with **0 errors, 0 warnings, 0 lints**.
- [ ] `flutter test` passes 100% of unit and invariant tests.
- [ ] No `.apk` binaries or secrets checked directly into Git tracked files.
- [ ] Live demo is active and accessible on Firebase Hosting.
- [ ] High-contrast, authentic UI theme verified on mobile and web viewports.
- [ ] PR branch pushed cleanly to `origin/<branch-name>`.

---
**GDG Cloud Bengaluru — Road to Devfest: Open Source Edition**  
*Fork with ambition. Build with precision. Merge with pride.* 🏆
