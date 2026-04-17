from __future__ import annotations

import os
from datetime import date
from typing import Iterable, List, Optional, Tuple

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt


BRAND = {
    "name": "Bharat Dues",
    "tagline": "UPI-first group settlements",
    "accent": RGBColor(0xFF, 0x8F, 0x00),  # warm amber
    "secondary": RGBColor(0xA7, 0x8B, 0xFA),  # lavender
    "dark": RGBColor(0x0F, 0x0E, 0x17),
    "card": RGBColor(0x1A, 0x19, 0x27),
    "text": RGBColor(0xFF, 0xFF, 0xFF),
    "muted": RGBColor(0xC7, 0xC7, 0xC7),
}


def _set_run_style(run, *, bold: bool = False, size: int = 22, color: RGBColor = BRAND["text"]):
    run.font.bold = bold
    run.font.size = Pt(size)
    run.font.color.rgb = color
    run.font.name = "Aptos"


def _set_shape_fill(shape, rgb: RGBColor):
    fill = shape.fill
    fill.solid()
    fill.fore_color.rgb = rgb
    shape.line.fill.background()


def _add_title(slide, title: str, subtitle: Optional[str] = None):
    # Use a blank layout and draw our own text boxes for predictable formatting.
    left = Inches(0.8)
    top = Inches(0.9)
    width = Inches(12.0)
    height = Inches(1.2)
    tx = slide.shapes.add_textbox(left, top, width, height)
    p = tx.text_frame.paragraphs[0]
    p.alignment = PP_ALIGN.LEFT
    run = p.add_run()
    run.text = title
    _set_run_style(run, bold=True, size=42, color=BRAND["text"])

    if subtitle:
        sub = slide.shapes.add_textbox(Inches(0.82), Inches(2.05), Inches(12.0), Inches(0.8))
        p2 = sub.text_frame.paragraphs[0]
        p2.alignment = PP_ALIGN.LEFT
        r2 = p2.add_run()
        r2.text = subtitle
        _set_run_style(r2, bold=False, size=20, color=BRAND["muted"])


def _add_bullets(slide, title: str, bullets: Iterable[str], *, note: Optional[str] = None):
    _add_section_header(slide, title)
    left = Inches(0.9)
    top = Inches(1.8)
    width = Inches(12.0)
    height = Inches(5.2)
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.clear()
    for idx, b in enumerate(bullets):
        p = tf.paragraphs[0] if idx == 0 else tf.add_paragraph()
        p.text = b
        p.level = 0
        p.space_after = Pt(8)
        for run in p.runs:
            _set_run_style(run, size=22, color=BRAND["text"])

    if note:
        nb = slide.shapes.add_textbox(Inches(0.9), Inches(6.95), Inches(12.0), Inches(0.6))
        p = nb.text_frame.paragraphs[0]
        p.text = note
        for run in p.runs:
            _set_run_style(run, size=14, color=BRAND["muted"])


def _add_section_header(slide, title: str):
    bar = slide.shapes.add_shape(
        1,  # MSO_SHAPE.RECTANGLE (avoid importing enum to keep script simple)
        Inches(0.6),
        Inches(0.45),
        Inches(12.8),
        Inches(0.85),
    )
    _set_shape_fill(bar, BRAND["card"])
    tx = slide.shapes.add_textbox(Inches(0.9), Inches(0.62), Inches(12.0), Inches(0.6))
    p = tx.text_frame.paragraphs[0]
    r = p.add_run()
    r.text = title
    _set_run_style(r, bold=True, size=26, color=BRAND["text"])


def _set_slide_background(slide, rgb: RGBColor = BRAND["dark"]):
    bg = slide.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = rgb


def _add_footer(slide, right_text: str):
    tx = slide.shapes.add_textbox(Inches(0.8), Inches(7.05), Inches(12.2), Inches(0.4))
    tf = tx.text_frame
    tf.clear()
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.RIGHT
    r = p.add_run()
    r.text = right_text
    _set_run_style(r, size=12, color=BRAND["muted"])


def _add_logo(slide, logo_path: str):
    if not os.path.exists(logo_path):
        return
    slide.shapes.add_picture(logo_path, Inches(10.9), Inches(0.35), height=Inches(0.65))


def build_deck(output_path: str, *, logo_path: Optional[str] = None) -> str:
    prs = Presentation()
    # Force widescreen (16:9)
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    def new_slide() -> Tuple:
        slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
        _set_slide_background(slide)
        if logo_path:
            _add_logo(slide, logo_path)
        _add_footer(slide, f"{BRAND['name']} • {date.today().isoformat()}")
        return slide

    # Slide 1 — Title
    s1 = new_slide()
    _add_title(
        s1,
        f"{BRAND['name']}",
        "App guide: what it does, how it works, and key functions",
    )
    if logo_path and os.path.exists(logo_path):
        # Big center logo
        s1.shapes.add_picture(logo_path, Inches(0.9), Inches(3.0), height=Inches(2.0))

    # Slide 2 — Agenda
    s2 = new_slide()
    _add_bullets(
        s2,
        "Agenda",
        [
            "What the app is (and who it is for)",
            "How it works (real-time shared ledger)",
            "Core functions: groups, expenses, balances, settlements",
            "UPI + QR flow and payment confirmation",
            "Analytics and activity history",
        ],
    )

    # Slide 3 — What is Bharat Dues
    s3 = new_slide()
    _add_bullets(
        s3,
        "What is Bharat Dues?",
        [
            "A Splitwise-style shared expense tracker focused on UPI-first settlements in India",
            "Designed for roommates, trips, friends, and any group with shared bills",
            "Real-time sync: everyone sees the same group ledger instantly",
        ],
        note="Based on `README.md` and implemented in Flutter + Firebase.",
    )

    # Slide 4 — How it works (architecture)
    s4 = new_slide()
    _add_bullets(
        s4,
        "How it works (in simple terms)",
        [
            "Each group is stored in Firestore as a shared document: members + aggregated net balances",
            "Expenses and settlements are stored in sub-collections and streamed live to every member",
            "Balances are computed from expenses + confirmed settlements; “simplify debts” reduces transfers",
        ],
        note="See `lib/providers/app_state.dart` and `lib/utils/settlement_helper.dart`.",
    )

    # Slide 5 — User journey
    s5 = new_slide()
    _add_bullets(
        s5,
        "Typical user journey",
        [
            "Sign in with Google (OTP flow exists but can be disabled)",
            "Complete onboarding/profile guard if Firestore profile is missing",
            "Set your UPI ID in Profile (recommended for one-tap settlements)",
            "Create or join groups, then start adding expenses",
        ],
        note="Routing is handled in `lib/screens/app_shell.dart`.",
    )

    # Slide 6 — Home dashboard (Groups)
    s6 = new_slide()
    _add_bullets(
        s6,
        "Home screen: your dashboard",
        [
            "Shows your overall net position: You owe vs You are owed",
            "Lists your groups (and optionally 1-on-1 “Friends” groups via feature flag)",
            "Quick actions: edit profile (UPI/phone), create a new group, sign out",
        ],
        note="See `lib/screens/home_screen.dart`.",
    )

    # Slide 7 — Create group + members
    s7 = new_slide()
    _add_bullets(
        s7,
        "Groups and members",
        [
            "Create a group with a name and members (contacts/guests supported)",
            "Members are stored with identifiers (UID and/or phone) for reliable lookup and access",
            "Group membership enables real-time collaboration: any member can add expenses",
        ],
        note="Core group model: `groups/{groupId}` with `members`, `memberIds`, `memberIdentifiers`.",
    )

    # Slide 8 — Add expense (splits + categories)
    s8 = new_slide()
    _add_bullets(
        s8,
        "Add an expense (the heart of the app)",
        [
            "Enter description, amount, and who paid",
            "Split modes include equal split and exact/custom splits (additional modes exist in helper logic)",
            "Category is auto-detected from description but can be manually overridden",
            "Expense instantly updates group balances for all members",
        ],
        note="Expense modal + category detection live in `lib/screens/group_settlement_screen.dart`.",
    )

    # Slide 9 — Balances + simplify debts
    s9 = new_slide()
    _add_bullets(
        s9,
        "Balances and “Simplify Debts”",
        [
            "For each member: Positive balance = they should receive money; Negative = they owe",
            "The app can simplify the settlement into the minimum set of transfers (greedy matching)",
            "Confirmed settlements reduce debts; pending/disputed do not change balances",
        ],
        note="See `computeMemberBalances()` + `_settleBalances()` in `lib/utils/settlement_helper.dart`.",
    )

    # Slide 10 — Settle up with UPI / QR / confirmations
    s10 = new_slide()
    _add_bullets(
        s10,
        "Settle Up (UPI-first flow)",
        [
            "Shows recommended transfers (A pays B ₹X) based on simplified transactions",
            "If receiver has a UPI ID: generate a UPI deep-link + QR code and pay via any UPI app",
            "After paying, the app asks for confirmation (since UPI apps don’t return status callbacks)",
            "Payments are recorded as Pending and only update balances once the receiver confirms",
            "If no UPI ID is available: record a manual payment and reconcile later",
        ],
        note="UPI deep link: `lib/utils/upi_helper.dart`; settle UI: `lib/screens/group_settlement_screen.dart`.",
    )

    # Slide 11 — Analytics + activity
    s11 = new_slide()
    _add_bullets(
        s11,
        "Analytics and history",
        [
            "Category-wise spending breakdown for the group (bar-style list)",
            "Activity feed merges expenses + settlements chronologically",
            "Search expenses inside a group for quick audits",
        ],
        note="Analytics sheet is implemented as `_AnalyticsSheet` in `lib/screens/group_settlement_screen.dart`.",
    )

    # Slide 12 — Reliability + integrity
    s12 = new_slide()
    _add_bullets(
        s12,
        "Built for stability and financial integrity",
        [
            "Profile guard: if user profile is missing, onboarding is forced to restore integrity",
            "Balance locks: prevents destructive actions until balances reach ₹0 (where configured)",
            "Soft delete for groups (Undo support) to avoid accidental data loss",
            "Firestore streams for real-time sync and consistent UI state",
        ],
        note="See `lib/screens/app_shell.dart`, `lib/providers/app_state.dart`.",
    )

    # Slide 13 — Tech stack
    s13 = new_slide()
    _add_bullets(
        s13,
        "Tech stack & integrations",
        [
            "Flutter (Material 3) UI with Provider state management",
            "Firebase: Authentication, Firestore (shared-ledger), Cloud Messaging",
            "UPI deep-linking and QR generation for settlements",
            "Sharing and reminders: Share sheet and WhatsApp deep-linking (when available)",
        ],
        note="Dependencies are listed in `pubspec.yaml`.",
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    prs.save(output_path)
    return output_path


if __name__ == "__main__":
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    logo = os.path.join(repo_root, "assets", "images", "logo.png")
    out = os.path.join(repo_root, "BharatDues_App_Guide.pptx")
    build_deck(out, logo_path=logo)
    print(out)

