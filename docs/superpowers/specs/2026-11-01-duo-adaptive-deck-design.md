# Adaptive laptop deck — design

## Summary

**What we're building**
- A new layout for the Duo's bottom screen in laptop pose, called **Adaptive**.
- When you're not typing, the whole bottom screen is one big trackpad.
- When you click into a text box or the terminal, a full keyboard slides in.
  - The trackpad shrinks to a laptop-sized pad under the keys.
- When you click away, the keyboard slides back out.
- A keyboard button opens or closes it by hand anytime.

**What it looks like**
- A row of shortcuts across the top: Esc, Search, All Windows, Undo, Redo, fn, keyboard.
- The mic and your custom Laptop Keyboard buttons sit in columns beside the trackpad.
- A "…" button holds the rest: keyboard layout, customize, Duo settings.
- It's modeled on the remote-desktop app in your screen recording.

**Why it matters**
- Today the deck shows the keyboard *or* the trackpad, and you switch by hand.
- Adaptive gives you a big trackpad most of the time, and keys only when you need them.
- You never have to flip modes.

**Today's deck stays**
- Settings › Laptop Keyboard gets a **Layout** choice: Adaptive or Classic.
- Adaptive is the default.
- Classic is today's deck, unchanged.

**Rough phases**
1. The new layout, with the keyboard button working by hand.
2. Automatic switching when you click into or out of a text box or the terminal.
3. Polish: animation, haptics, the "…" menu, accessibility, small and large screen checks.

---

## Decisions (agreed with Ryan, 2026-11-01)

- **Coexistence:** a setting, not a third deck toggle. Adaptive is the default; Classic is today's deck as-is.
- **When the keyboard appears:** automatically on text focus, plus a manual keyboard button that overrides either way.
- **Chrome:** option A from the mockups.
  - A shortcut row on top.
  - Side columns beside the trackpad.
  - No bottom bar.

## Behavior

### States

| State | Shortcut row | Middle | Side columns |
|---|---|---|---|
| Not typing | Esc · Search · All Windows · Undo · Redo · fn · ⌨︎ | Big trackpad, full width between the columns | Left: mic, then left custom buttons. Right: right custom buttons, then "…" |
| Typing | Same; ⌨︎ highlighted | Full keyboard (today's `DuoKeyboardView`), then a smaller trackpad | Same columns, beside the small trackpad only |

- **Hardware keyboard attached:** never show the keyboard.
  - The ⌨︎ and fn buttons are hidden.
  - The middle stays the big trackpad.
- **Hardware keyboard and mouse:** the deck is hidden, as today.
- **External monitor mode** (`DuoExternalDisplay`): it uses the same deck, so it gets the same Adaptive behavior.

### When the keyboard shows

The deck wants the keyboard while any of these is true:
1. **A LinPad text field or text view is editing.**
   - Examples: launcher search, Run dialog, rename fields.
   - Signal: UIKit begin/end-editing notifications, which `OnScreenKeyboard` already observes.
2. **The focused window is the LinPad terminal.**
3. **The focused Linux window has an enabled text input** (`LinuxSurface.textInput != nil`).
   - Linux apps report this through `zwp_text_input_v3`.
   - Example: clicking into Firefox's address bar.

**Manual override:**
- Tapping ⌨︎ forces the opposite of what's showing: open if closed, closed if open.
- The override lasts until the typing target changes: a different field or window gets focus, or focus leaves.
- After that, automatic behavior resumes.
- This covers Linux apps that don't report text input (some terminals, games).

**Hide delay:**
- The keyboard waits 0.3 s after focus leaves before hiding.
- Moving between two fields doesn't make it flicker.
- Showing is immediate.

### Shortcut row

| Button | Does | Notes |
|---|---|---|
| Esc | Escape key to the focused target | Same as today's `.escapeKey` action |
| Search | Opens the launcher with search | `.launcher` |
| All Windows | Overview | `.overview` |
| Undo | Linux window: Ctrl+Z. LinPad text field: its `undoManager`. | Does nothing in the terminal: Ctrl+Z there would suspend the running program |
| Redo | Linux window: Ctrl+Shift+Z. LinPad text field: `undoManager.redo()`. | Same terminal exception |
| fn | Locks F1–F12 on the number row | Today's `functionKeysLocked`. Always in the row (dimmed while the keys are hidden), so the buttons don't shift when typing starts |
| ⌨︎ | Manual override (above) | Accent-highlighted while the keyboard shows |

### Side columns and "…"

- **Left column:** the mic first.
  - Same `DuoMicButton` tap and hold behavior.
  - Smaller: 44 pt instead of the bar-height circle.
  - Then the left custom buttons from `DuoDeckLayout.leftButtons`.
- **Right column:** the right custom buttons from `DuoDeckLayout.rightButtons`, then "…" last.
- **When buttons don't fit:**
  - Each column shows as many 44 pt buttons as fit beside the current trackpad height.
  - The mic and "…" always show.
  - Custom buttons that don't fit move into the "…" menu.
  - This matters mostly in the typing state, where the pad is short.
- **The "…" menu holds:**
  - Keyboard layout, which moves here from today's top-strip chip.
  - Customize Keyboard…
  - iPhone Duo settings, which moves here from today's gear.
  - Any overflowed custom buttons.

### Trackpad

- The same `DuoTrackpad` in both states: clicks, drags, two-finger scroll and fling all carry over.
- The hint caption shows on the big pad only.
- **Small-pad width:** about 60% of the deck, centered, like a MacBook's.
- **Small-pad height:** whatever is left under the keys, with a minimum of 80 pt.
  - When the deck is too short for that, the keyboard rows compress first.

### Motion and feel

- **Keyboard in and out:** the keys slide down from the shortcut row while the trackpad shrinks, with `DesktopMotion.standard`.
  - With Reduce Motion on, it's a cross-fade instead.
- **Haptics:** a light impact when the keyboard appears or leaves because of the ⌨︎ button. Automatic changes get none, to avoid buzzing on every focus change.
- **Tap targets:** 44×44 pt minimum. SF Symbols for icons. Dynamic Type on labels; the key caps keep today's sizing.

## Architecture

- **`DuoDeckStyle`:** an enum with `.adaptive` and `.classic`.
  - Stored with `@AppStorage("duo.deck.style")`, defaulting to `.adaptive`.
  - Settings › Laptop Keyboard (`DuoSettingsSection`) gets a segmented picker.
- **`DuoInputDeck`:** branches on the style.
  - Classic: today's body, moved unchanged into `DuoClassicDeck`.
  - Adaptive: a new `DuoAdaptiveDeck` view.
- **`DuoTypingFocus`:** a new `@Perceptible @MainActor` model, owned by `DesktopController`.
  - Exposes `wantsKeyboard: Bool`.
  - Watches the three signals above.
  - Applies the override and the hide delay.
  - Inputs come in as small methods (`textEditingBegan/Ended`, `focusChanged(to:)`, `linuxTextInputChanged(_:)`, `toggleOverride()`), so the logic can be unit-tested without UIKit.
- **Signals:**
  - **Text fields:** `OnScreenKeyboard`'s existing begin/end-editing observers forward to `DuoTypingFocus`.
  - **Terminal and Linux focus:** observed from the window manager's focused window and the focused `LinuxSurface.textInput`, both Perceptible already.
- **`DuoAdaptiveDeck` view tree:**
  - `VStack`: the shortcut row, then a middle `ZStack`.
  - The middle animates between big-pad and keys-plus-small-pad.
  - The side columns are laid out with a `GeometryReader` to work out how many buttons fit.
- **Undo/Redo:** two new `DuoDeckAction` cases (`.undo`, `.redo`) handled in `DuoKeyboard.perform`.
  - Routing: Linux key chords through the existing key path; `undoManager` for UIKit responders; no-op in the terminal.
  - They become available as custom-button choices too.

## Testing

- **Unit tests for `DuoTypingFocus`:**
  - Each signal turns `wantsKeyboard` on and off.
  - The override flips it and resets on focus change.
  - The hide delay suppresses flicker between fields.
  - A hardware keyboard keeps it off.
- **Unit tests for column fitting:** the button count for given heights, and what overflows into "…".
- **Undo/Redo routing:** the terminal no-op, and the chord sent to Linux windows.
- **Simulator screenshots:** the Duo simulator in laptop pose (hinge 120° via `duoctl`).
  - Both states, smallest and largest installed iPhones.
  - Check truncation in the shortcut row.
- **On device:**
  - Click into launcher search, Firefox's address bar, and the terminal, then click away.
  - Confirm the keyboard comes and goes, and the ⌨︎ override works.

## Out of scope

- Customizing the shortcut row. It's fixed for now; the side columns stay customizable.
- Changes to Classic.
- iPad and non-Duo layouts. The deck only exists on the Duo.
