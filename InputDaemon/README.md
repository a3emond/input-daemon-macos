
# input-daemon

A lightweight macOS HID-level event tap that inverts mouse wheel scrolling while leaving trackpad gestures untouched.
Fixes the initial “trackpad shake” problem caused by naïve inversion of inertia tail events in chromium-based apps.

---

## Features

- **Scroll inversion (mouse only):** Natural-scroll toggle for traditional mice, without breaking trackpad gestures.
- **Trackpad-safe:** Uses event-rate + continuous flags to classify input correctly, so trackpad drag + momentum are never inverted.
- **State machine classifier:** Keeps a short buffer of recent events and applies heuristics to detect device type.
- **Idle/session reset:** Automatically clears context between gestures and when switching between mouse ↔ trackpad.
- **Hotkeys: (extra)**
  - `Ctrl+Shift+S` → Launch **Screenshot.app** (macOS screenshot UI).
  - `Ctrl+\` (while holding Ctrl) → Launch **iTerm**.
  - `Ctrl+Shift+R` → Reset the classifier (testing/debug).

---

## How it works

At the macOS HID layer, scroll events expose limited metadata:

- `kCGScrollWheelEventIsContinuous` (99): 1 for pixel/continuous scrolls (trackpads).
- `kCGScrollWheelEventPhase` (22) / `…MomentumPhase` (23): gesture phase and inertia state (often zero at `.cghidEventTap`).

These fields are not reliable enough alone.
Instead, the daemon uses a **classifier**:

1. Continuous flag → Trackpad.
2. High event rate (≥ `TRACKPAD_RATE_MIN` in `RATE_WINDOW_MS`) → Trackpad.
3. Otherwise → Wheel.

This ensures:

- Trackpad inertia tails stay classified as trackpad.
- Slow wheels are not mistaken for trackpads.

Scroll inversion is applied **only** to wheel-like streams.

---

## Configuration

You can tweak constants in `input-daemon.swift`:

fileprivate let MAX_HISTORY        = 32    // samples kept
fileprivate let IDLE_RESET_MS      = 100.0 // idle gap → reset buffer
fileprivate let RATE_WINDOW_MS     = 100.0 // rate-measure window
fileprivate let TRACKPAD_RATE_MIN  = 6     // events per window → trackpad
fileprivate let SMALL_DELTA_LIMIT  = 15    // “small” point delta cutoff
fileprivate let SMALL_RATIO_REQ    = 0.60  // ratio for borderline cases

- **Wheel misclassified as trackpad?**
  Raise `TRACKPAD_RATE_MIN` or lower `SMALL_RATIO_REQ`.

- **Trackpad misclassified as wheel (very gentle scroll)?**
  Lower `TRACKPAD_RATE_MIN` or increase `RATE_WINDOW_MS`.

---

## Testing

- **Mouse wheel** (slow + fast spins):
  Inverted correctly. No jitter at gesture end.

- **Trackpad gestures** (scroll, fling, momentum):
  Passed through unchanged. No inversion during inertia.

- **Switching devices**:
  Clean transitions — no contamination from previous buffer state.

---

## License

MIT License — do whatever you like, attribution appreciated.

---

## Credits

Developed to make macOS scrolling smooth and predictable.
Inspired by issues with Chromium’s handling of HID scroll tails.
