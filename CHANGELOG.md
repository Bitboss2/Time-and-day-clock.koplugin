# Changelog

This document compares **Atelier Clock 0.3.0** with the **latest version published on GitHub**, *Time & Day* (`dtdisplay`, commit `58930ab`). Changes are grouped by origin:

- **Part A**: the Atelier Clock work up to **0.2.5-beta.9**, the archive used as the base.
- **Part B**: **0.3.0**, which rebuilds the interface for 30 Hz, integrates Fluid Ink, adds multi-reader RTC, an English interface and the 10-minute refresh.

Part C maps every *Time & Day* feature to its current equivalent.

---

## Overview

| | GitHub: Time & Day | 0.2.5-beta.9 | **0.3.0** |
|---|---|---|---|
| Name and folder | `dtdisplay`, files at the repository root | `atelierclock.koplugin` | same |
| Faces | 5 hard-coded styles | 10 `.clock` v2 faces (ZIP + JSON + textures), v1/v2 import | same, English metadata |
| Customisation | Menu and slider customizer | Collection, variants, complication slots, v1 free editor | Same scope, redesigned interface |
| Interface | KOReader widgets, English | Native full-screen canvas, numbered pages, French | **Animated 30 Hz canvas: inertial scrolling, carousel, sheets, transitions. English** |
| Display | KOReader refreshes | KOReader refreshes, tight windows (≤ 4) | **Built-in Fluid Ink 6.5** (Pulses 2 / v6), classic fallback |
| Refresh profiles | Every minute | 1, 5 or 15 min, or static | **1, 5, 10 or 15 min, or static** |
| RTC | Minute wake-up loop | Single RTC task, Kobo Aura 2 adapter, FP9928 standby | **+ Kindle (powerd/mockrtc), checked on 10 models, fixes** |
| Diagnostics | — | Details, JSON export, session report | **+ display engine and RTC capability** |
| Tests | None | 156 | **169** |
| Licence | AGPL-3.0 | MIT (code) + CC0 (faces) | MIT (Atelier code) + GPL/AGPL engine; the whole follows `LICENSE` |

---

## Part A — from Time & Day to Atelier Clock 0.2.5-beta.9

This part summarises betas 1 to 9. Atelier Clock is an independent rewrite: its code does not reuse *Time & Day* or `dtdisplay`.

### Architecture

- The plugin is split into modules:
  - `core`: settings, calendar, time zones, collection, literal import of old profiles;
  - `packages`: ZIP/JSON reading and validation, export;
  - `render`: v1/v2 engines, retained tiles, changed regions;
  - `power`: RTC task, Kobo adapter, measurements, kernel evidence;
  - `integration`: sleep screen and menus;
  - `ui`: gallery and studio.
- One service is shared by the reader and file manager instances. No global `package.path` change.
- Settings are validated against a schema, written atomically to `settings/atelierclock/settings.json`, and tolerate old values.

### Faces

- **`.clock` v2 format**: a ZIP (DEFLATE) holding a JSON manifest, original PNG textures and a preview rendered by the Lua engine. The schema is in `docs/clock.schema.json` and `docs/CLOCK_FORMAT.md`. v1 files remain readable.
- **Ten original faces**: Totem, Duplex, Index, Halo, Journal, Lisière, Mosaïque, Octant, Typo, Signal. Each has its own portrait **and** landscape layout.
- **Styles** Bold, Thin and Outline. **Appearances** Paper, Ink and Auto.
- **Offline complications**: Empty, Date, Battery, Day, Week, World clock (bundled IANA transitions 1970–2100) and Reading, in three families: line, ring and rectangle.
- **"My faces" collection**: up to 24 independent variants, which can be duplicated, renamed or removed.
- **`.clock` import and export**, validated, never overwriting an existing file.
- **Settings profiles** in JSON, plus import of old Lua files (literal tables only, no code executed).

### Rendering

- v2 engine with retained tiles: background, decoration and date are not redrawn every minute, and hours and minutes are drawn separately.
- BB8 tile comparison (`render/delta.lua`), with at most four refresh windows, identical rows skipped with `memcmp`, and bounded fallbacks.
- Sleep refreshes in `ui` mode, without consuming the reader's page counter. Configurable full refreshes.
- Interface scaled to the real DPI, reflowed for landscape and small screens.
- Single-image or slideshow PNG backgrounds, per-image settings (`image.png.json`), inversion in dark mode.

### Power and RTC

- One RTC task with a stable callback reference. Changes are deferred out of `wakeupAction`, other alarms in the queue are respected, and the physical alarm is cleared when it belongs to the plugin.
- Refresh profiles: 1, 5 or 15 minutes, or static. Night pause, and a battery threshold that stops wake-ups.
- Guard against alarms that fall during suspend preparation (4 s minimum lead).
- Kobo Aura 2 optimisations:
  - priority wake-up (`fast_rtc`);
  - conditional reuse of the suspend preparation (`_doSuspend`);
  - bounded retries after a short return;
  - native standby until the minute alarm once the FP9928 refusal is confirmed (beta 9).
- Sleep measurements (BOOTTIME/MONOTONIC clocks), bounded kernel log reading, `diagnostic.json` and `last-session.json` reports.

### 0.2.5 interface

- Full-screen studio with four tabs: Faces, Edit, Sleep and Diagnostics. French labels.
- Face browser with arrows and swipes, "+ Add" catalogue.
- Slot editor with a complication picker that renders each complication live.
- Draft with Cancel and Apply.
- Paginated diagnostics.

### Validation

- 156 desktop tests, with LuaJIT, pinned real KOReader modules and libarchive.
- Replays of user sessions, PMIC and RTC simulations.
- Native KOReader integration on x86_64 and ARMv7 (QEMU).
- No electrical measurement is claimed.

---

## Part B — from 0.2.5-beta.9 to 0.3.0 (this work)

### 1. Built-in Fluid Ink 6.5 engine

**New files**

- `engine/fluidink/`: **unmodified** copy of `native.lua`, `platform.lua` and `startup.lua`, the binaries `libinkmotion-arm.so` and `libinkmotion-kindlepw2.so` (ABI 6500), `noise64.bin`, `COPYING` and `THIRD_PARTY_NOTICES.md`.
- `third_party/fluid-ink/`: the matching C sources, build script and protocol documents. The personal copy `factory-reference.bin` is **not** redistributed (see `.gitignore`).
- `engine/profile.lua` picks the display profile:

| Case | Profile |
|---|---|
| `Kobo_star` with a verified custom path | **Fluid Ink v6** (policy 12), **Pulses 2**, **Throughput** (queue 1, Bayer 8×8, no gamma), A2, 30 fps |
| Other compatible models | **v6 without pulses** (vendor policy 2, or 12 on the custom path), A2 while moving and DU at rest |
| Pulses refused (`phase_errno`) | Switches to v6 without pulses without leaving the engine |
| "Classic" setting, or model not on the list | Classic |

- `engine/display.lua` is the single owner of the studio's screen. It follows the lifecycle of Fluid Ink's `demo.lua`:
  - RAM check in a child process (`startup.lua`), with the result cached for the session;
  - worker start, then `setPhase(2, 12)` on the Aura 2 v1;
  - frame publishing with the rest flag (`im_set_still`);
  - monitoring of EPDC errors, worker exit and the watchdog: wait for neutralisation, free, then fall back to classic;
  - asynchronous release (stop → reap → `free`, which restores the LUT and capture), plus a bounded synchronous release for sleep and emergency close;
  - resume after text entry or wake-up.
- The engine stays off in landscape, in night mode, without an mxcfb framebuffer, or when the check fails. The reason is shown in Diagnostics.

**New settings**: `display_engine` (auto, fluid, classic), `display_fps` (30, 45, 60), `display_rest` and `motion` (full, reduced). They are validated in `core/settings.lua`.

**Diagnostics**

- The *Display* section shows the active engine, its profile, live targets and scans per second, and the settings. It also offers "Clean the screen" and "Retry the fluid engine".
- `diagnostic.json` now includes `display` and `rtc_capability`.

### 2. Interface redesigned for 30 Hz

The rendering is entirely new (`ui/studio.lua`, `ui/views.lua`, `ui/faces.lua`, `ui/studio_actions.lua`):

- **Layered composition** into an 8-bit buffer: header, scrolling content, carousel, draft bar, toast, tab bar, sheet.
  - Text and face previews are rendered once and cached.
  - Each frame is just a set of blits plus a few shapes.
  - Animated elements (switches, counters, segments, sliders) are redrawn in place.
- **A single animation loop** at the chosen frame rate. It skips missed deadlines and never queues stale frames. At rest it stops, publishes one last "still" frame, and a slow health watch takes over.
- **In classic mode or with reduced animations**, everything jumps to its final state. While a finger is dragging, there is at most one `fast` refresh every 0.2 s.
- **`ui/motion.lua`**: easing, damped springs, an inertial scroller (filtered velocity and exponential decay, in the spirit of `engine.lua`) with a continuous elastic edge and snapping, and deadline handling.
- **`ui/kit.lua`**: a complete visual system.
  - Colours: paper, ink, and three light greys (wash, shadow, hairline).
  - Text sizes: 6.
  - Components: cards with soft shadows, pill buttons, icon button, switch, segmented control, settings row, section titles, gauge, page dots.
- **`render/draw.lua`**: rounded rectangles and outlines drawn by scanline, round-capped strokes, arcs.
- **`ui/icons.lua`**: 38 redrawn icons on a 24-unit grid, with rounded strokes.

**Screen by screen**

- **Faces**
  - Carousel: drag, fling (at least one card, at most three), snap. Neighbours peek in and fade, with page dots.
  - *My faces / Catalogue* switch with a gliding pill.
  - ⋯, Edit, Use and Show buttons. The ⋯ sheet offers Duplicate, Rename, Show full screen and Remove.
  - A long press on the card opens the actions.
- **Edit**
  - *Style / Modules / Options* segments with a sideways transition. A horizontal swipe changes mode.
  - Slots carry a "+" badge.
  - The **modules sheet** shows each complication rendered live. When you pick one, a frame flies to its slot and pulses.
  - Style: "12" specimen chips, and Paper / Ink / Auto with icons.
  - Options: grouped list (name, export, orientation, time format, clock language, date, interface size).
- **Sleep**
  - Main card with the sleep screen switch.
  - Refresh as a segmented control, with its precision shown underneath.
  - *Wake-up* card: the model's RTC capability, Aura 2 priority wake-up, "Optimise for Aura 2".
  - Advanced settings in the same scrolling list, with no sub-page.
- **Diagnostics**
  - Battery gauge and counters that count up to their value.
  - Next update and Display section.
  - Tools: technical details expanded inline, export and profile.
- **v1 free editor**: draggable preview, element choice in a sheet, six section tiles, settings as a list.

**Navigation**

- Tab bar with a gliding pill, sideways transitions between tabs, horizontal swipe to change tab.
- Back button in the header of sub-views; the Back key closes the open sheet first.
- Touch feedback: a light tint on the touched area. A finger stops a running scroll dead.

**Other changes**

- Confirmations and choices in custom sheets: KOReader no longer takes the screen back for a simple "Remove?".
- Short toasts instead of the status line.
- The *Draft* bar appears only when there are changes.
- "Show" zooms the preview to full screen with KOReader's MuPDF scaler. If it is unavailable, the preview is revealed by cropping, never by the `BlitBuffer:scale` Lua loop.
- Rotation change: the engine is released, then the layout is rebuilt.
- Sleep: synchronous stop, before the sleep screen draws.

### 3. English interface, 10-minute refresh

- **The whole interface is in English**: studio, sheets, toasts, settings labels, Diagnostics, KOReader menus and Dispatcher actions, sleep-screen menu entry ("Atelier clock"), notices, RTC reasons, and `.clock` import and validation errors.
- **Face manifests in English**: subtitles, categories, slot names, author, and Index's "THROUGH THE DAY" label. The ten faces were regenerated with `tools/build_assets.py`. Face names stay as they are (Totem, Lisière, Mosaïque…).
- **Clock language**: faces keep their *Clock language* setting (English or French). The default for new installations is now English; a saved setting is kept. Status notes drawn on the clock (low battery, no RTC, updates stopped, "≈ updated every N min") follow that language.
- **Fix**: the English time in words (Typo face) used to read "14 hours / 37 minutes". It now reads "two / thirty-seven", "seven / o'clock", "noon / exactly".
- **New 10-minute refresh profile**: a *10 min* segment in Sleep, validated in the settings, scheduled with alignment on the 10-minute mark, and shown on the clock as "≈ UPDATED EVERY 10 MIN". Neither Time & Day (every minute only) nor 0.2.5-beta.9 (1/5/15 min, static) had it.

### 4. RTC on every compatible reader

- `power/capabilities.lua` works out, from KOReader's device classes, whether wake-up goes through the Kobo RTC, through powerd on Kindle, or is unavailable.
- `power/kindle.lua` is new. On Kindle, powerd suspends the reader and KOReader calls `setRtcWakeup` on `readyToSuspend`. A guard placed just after each deadline calls `recoverDue()` in two cases:
  - the reader stayed awake in sleep-screen mode;
  - `readyToSuspend` dropped an alarm that was already in the past.

  It never runs another task's callback.
- **Fix**: without `WakeupMgr`, the session was marked active with no alarm. It is now inactive, and the "no RTC / time frozen" note is shown.
- **Fix**: on an i.MX5 RTC (`dodgy_rtc`), the first link of the alarm chain for a long night pause stayed programmed after stopping. It is now cleared when it belongs to the plugin.
- Diagnostics and report: RTC capability and Kindle recoveries.

### 5. Tests and tools

- **`tests/test_rtc_devices.py`** (new, 5 tests):
  - the 7 Kobo models;
  - the `dodgy_rtc` chain;
  - the 3 Kindles in four scenarios: scheduled wake-up 10 s early, prolonged wake, dropped alarm, stop;
  - a Kindle without the KOReader sleep screen;
  - the complete 10-minute profile: settings, Sleep tab, scheduler.

  These tests use the real `wakeupmgr.lua`, the real `kindle/mockrtc.lua` and the wake-up functions of `kindle/powerd.lua`.
- **`tests/test_fluid_ui.py`** (new, 8 tests):
  - profiles per model and motion models;
  - start with Pulses 2 / Throughput, with no KOReader refresh while the engine runs;
  - carousel and modules sheet;
  - text entry with release then resume;
  - sleep and wake, refused pulses, watchdog;
  - reduced animations and animated switch;
  - frames in motion.
- Existing tests adapted:
  - the contrast test allows the three greys of the visual system but still bans mid-grey fills;
  - the version is read from `core/version.lua`.
- The test harness gains `darkenRect`, `lightenRect` and a test `ui/renderimage`. `fetch_test_dependencies.py` fetches `kindle/mockrtc.lua` and `kindle/powerd.lua`.
- **`tools/build_screenshots.py`** produces the screenshots and GIFs from frames actually published at 30 Hz on a deterministic clock, plus a simulation of the Bayer 8×8 dithering.
- `tools/build_release.py`: version 0.3.0, at least 168 tests, and a `display` / `rtc_models` block in `RELEASE.json`.
- KOReader's plugin validator (skill `koreader-plugin`): 0 errors. The only warning concerns the `name` field of `_meta.lua`, which is kept.

### 6. Repository and documentation

- The repository adopts the Atelier layout: `atelierclock.koplugin/`, `tools/`, `tests/`, `validation/`, `third_party/` and `docs/media/`. The old *Time & Day* files remain in the git history.
- `README.md`, `CHANGELOG.md`, `docs/FEATURES.md` and the plugin README are in English.
- The developer and investigation notes (`DEVELOPPEMENT.md`, `docs/INVESTIGATION_*`, `docs/VALIDATION.md`, `docs/POWER_AURA2.md`) remain in French.
- Licences: Atelier code stays MIT and faces CC0. The engine's headers say GPL-3.0-or-later, but its package ships the AGPL-3.0 text; this should be confirmed by the engine's author. The distributed whole follows `LICENSE` (AGPL-3.0, as the repository did before).

### Known limits

- No measurement on a reader was possible here. Optical cadence, contrast, ghosting, the CPU cost of the studio at 30 Hz and Kindle wake-up still need to be checked on hardware.
- Screenshot fonts are substitutes (DejaVu).

---

## Part C — What became of the Time & Day features?

| Time & Day (GitHub) | Atelier Clock 0.3.0 |
|---|---|
| **Classic** style (time, date, battery) | Mosaïque, Duplex and Signal faces, and any face with the Date and Battery complications |
| **Fullscreen** style (stacked digits) | **Totem** face |
| **Outlined** style (outline over a PNG background) | **Outline** style, the v1 editor's *Digit outline* setting, PNG backgrounds |
| **Analog** style (ticks, hands, numerals) | **Halo** and **Octant** faces. v1 editor: Arabic, Roman or no numerals, hand widths |
| **Word Clock** (time spelled out) | **Typo** face, in English and French |
| Visual customizer on long press | Long press on the clock → **studio**, with live preview and draft |
| Overlap-free auto-layout, spacing | Designed slots in v2 faces. v1 editor: *Automatic layout* and *Spacing* |
| Decorative separators and frames | v1 editor → Finish: *Separator* (line, dots, diamond, ornament) and *Frame* (simple, double, corners) |
| Time and date fonts | v1 editor → Typography: font per element (KOReader name or TTF path) |
| Text size | Size per element, face scale, interface size |
| 12/24 h format, orientation, night mode | Options: time format, orientation (follow KOReader or four directions). Paper, Ink or Auto appearance (night mode) |
| PNG overlay, image or folder, interval | v1 editor → Images: single image or slideshow, portrait and landscape, duration, inversion in dark mode |
| Full refresh on image change | *Clean the screen on change* |
| Per-image settings (`*.lua`) | Per-image settings `image.png.json`, plus import of old Lua profiles (literal tables) |
| Clock frontlight (-1 = off) | *Frontlight* (-1 = keep) |
| Full refresh interval | *Full refresh* (minutes, 0 = off) |
| CPU awake time after refresh | *Margin after the display finishes* (0.1 to 5 s) |
| Per-minute RTC wake-up, fast suspend | Single RTC task and profiles of 1, 5, 10 or 15 min, or static. Aura 2 optimisations, Kindle through powerd |
| Menu launch and Dispatcher action | **Tools → More tools → Atelier Clock**, actions *open the studio* and *show the clock* |
| "Show clock on sleep screen" sleep screen option | **Atelier clock** option in the sleep screen menu, and the switch in **Sleep** |
