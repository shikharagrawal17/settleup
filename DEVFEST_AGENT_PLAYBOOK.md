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

## 🛡️ The 8 Non-Negotiable Agent Guardrails

To prevent hallucination, state corruption, or rejected pull requests, the agent MUST enforce these guardrails at all times:

```
[GUARDRAIL 1: ZERO GHOST DEPENDENCIES]
Never add third-party packages that have unverified native bindings, break Gradle/CocoaPods, or lack active maintenance. Always prefer official Google open-source packages (e.g. google_generative_ai, cloud_firestore, firebase_core).

[GUARDRAIL 2: ZERO COMMITTED BINARIES (GIT HYGIENE)]
NEVER commit compiled artifacts (.apk, .aab, .mp4, .tar.gz, .zip) to Git tracking. Build binaries locally, place them in gitignored paths or project root (e.g. bharat-dues-release.apk in .gitignore), and distribute via release links or Firebase Hosting.

[GUARDRAIL 3: STRICT SECRET SANITIZATION]
Never hardcode API keys, service account JSONs, private tokens, or personal phone numbers. Always use compile-time environment definitions (--dart-define), secure local configs, or fallback demo modes.

[GUARDRAIL 4: MATHEMATICAL CONSERVATION LAW]
In any financial, split, or ledger engine, balance conservation is an inviolable invariant:
    ∑ (Balances of all members) ≡ 0.00
Always write automated unit tests proving this invariant across all mutation lifecycles.

[GUARDRAIL 5: ATOMIC BATCH MUTATION (NO DRIFT)]
Never execute un-batched fragmented writes across collections. Any change modifying a subcollection doc (expense/settlement) and an aggregate document (group netBalances) MUST execute inside an atomic batch or transaction.

[GUARDRAIL 6: ANTI-SLOP VISUAL DIRECTIVE]
Never use generic AI dark-glass gradients, unreadable low-contrast gray-on-gray text, or browser default typography. Strictly adhere to production design systems with AAA contrast ratios and Google Fonts (Outfit, Inter, Roboto).

[GUARDRAIL 7: DUAL-LAYER AI RESILIENCY]
Every AI feature must feature a two-tier architecture:
1. Instant local heuristic/regex parser (zero latency, offline).
2. Cloud/on-device Gemini/Gemma layer for semantic extraction and validation.
If network fails or quota is exhausted, the app must NEVER crash.

[GUARDRAIL 8: FAST-FORWARD MERGE CLEANLINESS]
All work must live on a dedicated feature branch (e.g. feat/devfest-google-ai). Commits must follow Conventional Commits (feat:, fix:, test:, docs:) and flutter analyze must pass with 0 issues.
```

---

## ⚡ High-Performance Code Optimizations

When auditing and hardening open-source engines, apply these architectural optimizations:

### 1. O(1) Canonical Member Indexing
Avoid repeated linear scans $O(M)$ over members across nested loops ($O(E \times S \times M)$). Build a hash index once per calculation cycle:
```dart
Map<String, String> buildCanonicalMemberIndex(List<GroupMember> members) {
  final index = <String, String>{};
  for (final m in members) {
    index[m.id] = m.id;
    if (m.uid != null && m.uid!.isNotEmpty) index[m.uid!] = m.id;
    if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
      final clean = cleanPhoneDigits(m.phoneNumber!);
      index[clean] = m.id;
      final rawDigits = m.phoneNumber!.replaceAll(RegExp(r'\D'), '');
      if (rawDigits.length >= 10) {
        index[rawDigits.substring(rawDigits.length - 10)] = m.id;
      }
    }
  }
  return index;
}
```

### 2. Floating-Point Precision Guardrail
IEEE-754 floating point arithmetic introduces infinitesimal artifacts (e.g. `-0.0` or `1.421085e-14`). Cleanse all balance maps before presentation:
```dart
for (final key in balances.keys.toList()) {
  final raw = balances[key]!;
  balances[key] = raw.abs() < 0.005 ? 0.0 : (raw * 100).round() / 100.0;
}
```

### 3. Self-Healing Reconciliation
If Firestore's cached denormalized aggregates drift from the underlying journal, automatically re-synchronize in the background:
```dart
if (needsReconciliation && (expenses.isNotEmpty || settlements.isNotEmpty)) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    appState.migrateGroupBalances(_group.id, balances, totalSpent);
  });
}
```

---

## 🎥 The Brag Skill & Demo Video Protocol

> **CRITICAL DIRECTIVE:** If a user, mentor, or judge asks for a video, demo reel, presentation, or pitch:  
> **YOU MUST USE THE BRAG SKILL WORKFLOW.**

### What is the Brag Skill?
The Brag Skill is an automated pipeline for generating developer showcase videos, pitch decks, and social demo reels using code-driven video synthesis (HTML/Remotion + WebP/MP4 recording).

### Brag Video Generation Workflow:

1. **Composition Brief (`brag-output/composition-brief.md`):**
   - Define target audience (GDE Judges, DevFest Attendees, Open Source Maintainers).
   - Core message: How Google Open Source & AI tools turned a buggy codebase into an audit-grade, high-performance application.
   - Format: 30–60 seconds, 1080x1920 (9:16 Portrait for Shorts/Reels) and 1920x1080 (16:9 Landscape for Stage).

2. **Visual Branding & Theme Alignment:**
   - **Google DevFest Palette:** Pure White, Google Blue (`#4285F4`), Red (`#EA4335`), Yellow (`#FBBC05`), Green (`#34A853`), and authentic App Brand Tokens (`#002E6E` Dark Blue, `#00B9F1` Cyan).
   - High-contrast typography with Outfit / Inter.
   - Zero AI-looking dark-glass slop; clean cards, real UI mockups, animated code diffs.

3. **Slide Progression Structure (30–45s Pitch):**
   - **Slide 1 (0–6s) — The Hook:** "Road to Devfest: Open Source Edition @ Google Ananta." Problem statement (e.g. balance drift & data mismatch).
   - **Slide 2 (6–15s) — The Engineering Fix:** Double-entry ledger audit, canonical ID resolution, 0.00 zero-sum conservation.
   - **Slide 3 (15–25s) — Google AI Integration:** Gemini/Gemma receipt scanning, structured schema extraction, offline heuristics.
   - **Slide 4 (25–35s) — The Results:** 0 lints, 100% test pass rate, live on Firebase Hosting, APK ready.
   - **Slide 5 (35–40s) — Call to Action:** "Fork, Build, Merge! Live on GitHub @gdgcblr."

4. **Automated Recording & Packaging:**
   - Open browser subagent to record preview animation to WebP video in artifacts.
   - Render MP4 using Remotion / FFmpeg into `brag-output/brag.mp4`.
   - Generate high-res cover thumbnail (`brag-output/brag.jpg`).
   - Create social copy variants for X (Twitter), LinkedIn, and GitHub Releases in `share-copy-variants.md`.

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
