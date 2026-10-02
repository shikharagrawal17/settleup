# Hyperframes Composition Brief: Bharat Dues

## Objective
Create a short, punchy, launch-style brag video for Bharat Dues.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080 (30 fps)
- Duration: 20.0 seconds

## Source Material
- Project root: `/Users/shikhar/Projects/settleup_lite`
- Primary files read: `README.md`, `PITCH_DECK.md`, `lib/main.dart`, `lib/widgets/app_shell_widgets.dart`, `docs/assets/logo.png`
- Product name: Bharat Dues
- Tagline / strongest claim: "Split Bills, Settle Beautifully — greedy debt simplification turns 10 tangled debts into 2 clean UPI payments."
- Key UI or visual moment to recreate:
  - Chaotic expense cards collapsing via Greedy Minimizer into 2 transfers
  - The UPI QR Code settlement modal with dynamic amount and instant "Payment Settled" confirmation
  - Bharat Dues branding with fintech glowing gradients
- Copy that must appear verbatim:
  - "Split Bills, Settle Beautifully."
  - "10 Tangled Debts → 2 Clean Transfers"
  - "Direct UPI Settlement"
  - "Double-precision accounting • WhatsApp Receipts"

## Creative Direction
- Tone preset: `polished`
- Creative direction: "Sleek Indian fintech product launch with crisp card motion, rhythmic beat sync, and satisfying UPI settlement payoff"
- Interpretation: Confident, modern, high-contrast fintech aesthetic with playful nods to the classic Indian group expense struggle.
- Angle: From group vacation chaos to effortless settlement in 2 taps.
- Hook: "Goa trip ended. 5 friends. 10 tangled debts. Who actually owes whom?"
- Outro / punchline: "Split Bills, Settle Beautifully."
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign

## Visual Identity
- Background: `#F5F7FA` (Clean fintech cool grey)
- Primary Blue: `#00B9F1` (Paytm / Fintech vibrant cyan)
- Dark Navy: `#002E6E`
- Card Surface: `#FFFFFF` with border `1px solid rgba(0, 46, 110, 0.08)` and box shadow `0 20px 40px -15px rgba(0, 46, 110, 0.07)`
- Success Green: `#00C853`
- Debt Red: `#FF3B30`
- Display font: `'Plus Jakarta Sans', system-ui, -apple-system, sans-serif`
- Body font: `'Inter', system-ui, -apple-system, sans-serif`
- Visual references from the project: Bharat Dues coin logo, UPI QR code card, Greedy Minimizer debt simplification routes.

## Storyboard
1. **Scene 1: The Group Expense Chaos** (0.0s – 4.0s) — Goa trip ended, chaotic red debt cards appear one by one ("Rohan owes ₹4,200", "Sneha owes ₹1,850", "Aarav owes ₹3,100"). "10 tangled transfers. Endless group chat drama."
2. **Scene 2: The Greedy Minimizer** (4.0s – 9.5s) — "Enter Algorithmic Harmony." The 10 tangled debts snap and collapse into just 2 clean transfers with a glowing green badge: "10 Debts → 2 Clean Transfers".
3. **Scene 3: 1-Tap UPI Settlement** (9.5s – 15.5s) — "One Tap. Direct UPI." Sleek UPI settlement card slides in with authentic QR code, ₹2,450.00 amount, and animated tap on "Pay via UPI" triggering an instant green checkmark and "Payment Confirmed & Net Handshake Recorded".
4. **Scene 4: The Outro & Punchline** (15.5s – 20.0s) — Screen transitions to deep navy/cyan gradient, Bharat Dues coin emblem drops in with glowing pulse: "Bharat Dues — Split Bills, Settle Beautifully."

## Audio
- Audio role: High-energy, confident modern fintech groove
- Music: `happy-beats-business-moves-vol-1-by-ende-dot-app.mp3`
- Music treatment: Volume 0.75, beat drop at 4.02s, rhythmic drive, fade out in last 1.5s.
- Music cue guidance: 120.19 BPM (~0.50s beat grid).
  - Beat-locked reveals: 4.02s (Scene 2 Minimizer drop), 9.52s (Scene 3 UPI card drop), 15.52s (Success checkmark chime), 17.02s (Logo slam).
- Audio-reactive treatment: Subtle; ambient background blue mist breathes gently with the music.
- Audio-coupled moments:
  - 0.5s–3.0s: Tactile card slide micro-clicks
  - 4.02s: Algorithmic crunch / digital sweep on minimization
  - 9.52s: Crisp card drop sound
  - 13.5s: Simulated button click
  - 15.0s: Rich settlement success chime
- Audio files: Copied into `brag-output/composition/assets/`

## Hyperframes Instructions
- Composition directory: `brag-output/composition/`
- Use Hyperframes standard architecture with `index.html`, clean vanilla CSS, and high-performance CSS / JS animations.
- Show actual UI elements: member cards, balance tags, UPI QR code, payment buttons, and the Bharat Dues logo.
- Keep all typography crisp, readable, with comfortable reading holds (minimum 1.2s per headline).
- Copy audio assets into `assets/music/` and `assets/sfx/`.
- Ensure zero errors on `npx hyperframes check`.
