"""Initial word-grid configuration.

Positions are explicit and MUST remain stable once a tablet is in use:
motor-planning stability for the user depends on buttons never moving.
New words may only be added to empty slots. Colors follow the Fitzgerald Key.
"""
from __future__ import annotations

# Fitzgerald Key color coding (matches SPEC.md design rules).
CATEGORY_COLORS = {
    "People": "#F5D63D",      # yellow
    "Needs": "#4CAF50",       # green
    "Feelings": "#2196F3",    # blue
    "Actions": "#4CAF50",     # green (verbs)
    "Places": "#9C27B0",      # purple
    "Time": "#FF9800",        # orange
    "Social": "#E91E63",      # pink
}

# Each entry: (text, tabler_icon, row, col). Tabler icon names match the
# webfont used by the frontend so words render identically across clients.
SEED_WORDS = {
    "People": [
        ("I", "ti-user", 0, 0),
        ("you", "ti-users", 0, 1),
        ("family", "ti-user-heart", 0, 2),
        ("doctor", "ti-stethoscope", 1, 0),
        ("nurse", "ti-nurse", 1, 1),
        ("friend", "ti-friends", 1, 2),
    ],
    "Needs": [
        ("water", "ti-droplet", 0, 0),
        ("food", "ti-soup", 0, 1),
        ("bathroom", "ti-toilet-paper", 0, 2),
        ("medicine", "ti-pill", 1, 0),
        ("rest", "ti-bed", 1, 1),
        ("help", "ti-help", 1, 2),
    ],
    "Feelings": [
        ("happy", "ti-mood-smile", 0, 0),
        ("sad", "ti-mood-sad", 0, 1),
        ("confused", "ti-mood-confuzed", 0, 2),
        ("frustrated", "ti-mood-angry", 1, 0),
        ("scared", "ti-mood-nervous", 1, 1),
        ("love", "ti-heart", 1, 2),
    ],
    "Actions": [
        ("stop", "ti-hand-stop", 0, 0),
        ("yes", "ti-circle-check", 0, 1),
        ("no", "ti-circle-x", 0, 2),
        ("more", "ti-plus", 1, 0),
        ("call", "ti-phone-call", 1, 1),
        ("again", "ti-repeat", 1, 2),
    ],
    "Places": [
        ("home", "ti-home", 0, 0),
        ("hospital", "ti-building-hospital", 0, 1),
        ("car", "ti-car", 0, 2),
        ("outside", "ti-sun", 1, 0),
        ("bathroom", "ti-bath", 1, 1),
        ("living room", "ti-sofa", 1, 2),
    ],
    "Time": [
        ("now", "ti-clock", 0, 0),
        ("today", "ti-sun", 0, 1),
        ("tonight", "ti-moon", 0, 2),
        ("tomorrow", "ti-calendar", 1, 0),
        ("before", "ti-arrow-back", 1, 1),
        ("later", "ti-arrow-forward", 1, 2),
    ],
}
