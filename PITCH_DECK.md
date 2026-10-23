# 🎙️ Bharat Dues — 3-Minute Hackathon Pitch Deck
**Event:** GDG DevFest Open Source Edition  
**Team:** Bharat Dues Core Team  
**Category:** Google Open Source & AI Technologies (Flutter + Firebase + Gemini)

---

## Slide 1: The Problem
> *"Splitting expenses with friends in India is broken."*
- **Typing Fatigue**: Manually typing 15 items from an optical restaurant bill or messy receipt.
- **Math Confusion**: Complex splits (e.g. 3 people drinking, 2 people only eating starters).
- **Awkward Conversations**: Reminding friends to pay back without seeming rude.
- **App Friction**: Traditional apps don't integrate directly with Indian UPI (GPay, PhonePe).

---

## Slide 2: The Solution — Bharat Dues
**A UPI-First, AI-Powered Shared Ledger built with Google Open Source.**
1. **📸 Snap & Split with Gemini 3.5 Flash**: Point your phone camera at a bill — Gemini extracts every line item, tax, and total in under a second.
2. **✨ Speak or Type Naturally**: *"Aman paid 1800 for dinner with Shikhar and Priya"* ➔ Gemini figures out who paid, who ate, and splits it automatically.
3. **⚡ Instant UPI Settlements**: 1-tap launch into GPay/PhonePe or dynamic QR code generation.
4. **🤝 High-Trust Handshake Lifecycle**: Inbound payment confirmations and instant WhatsApp verification.

---

## Slide 3: Live Demo Flow (90 Seconds)
1. **Show Dashboard**: Clean, modern financial health overview showing Net Balances.
2. **Tap "AI Split"**: Type *"Dinner ₹2100 with everyone, I paid"*.
3. **Watch Gemini in Action**: Form auto-fills, sets Food category, checks all group members, and computes equal shares.
4. **Show Receipt Scan**: Snap a bill photo on Web or Android; Gemini parses the total without manual typing.
5. **1-Tap Settlement**: Tap "Settle" ➔ launches GPay intent / generates dynamic UPI QR code.

---

## Slide 4: Google Open Source Tech Stack
| Component | Google Technology | Role |
| :--- | :--- | :--- |
| **Frontend** | **Flutter multi-platform** | Single codebase across Android, iOS, Web, macOS |
| **AI Engine** | **Google Gemini 3.5 Flash** | Multimodal OCR & conversational agent logic |
| **Backend** | **Firebase Firestore** | Real-time shared reactive ledger |
| **Authentication**| **Firebase Auth & GIS** | Cross-platform Google One-Tap & Popup Sign-in |

---

## Slide 5: The Impact & Next Steps
- **Production Ready**: Full double-precision accounting with epsilon validation.
- **Zero Privacy Leakage**: Gemini API keys configured locally by users; no middleman proxies.
- **Roadmap**: On-device Gemma inference via MediaPipe for offline receipt categorization on rural 2G/3G connections.
