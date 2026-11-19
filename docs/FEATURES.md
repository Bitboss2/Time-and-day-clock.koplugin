# Feature checklist: 0.2.5-beta.9 → 0.3.0

Every feature of the 0.2.5-beta.9 interface and where it lives in 0.3.0. ✅ = kept, ➕ = new.

## Faces

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| My faces: one large preview, ‹ › arrows and swipe | Carousel: drag, fling, snap, tap a neighbour, swipe | ✅ |
| Browsing never changes the active face | Unchanged (test `test_10`) | ✅ |
| + Add (catalogue of the ten models and imports) | **Catalogue** segment | ✅ |
| Add this face → variant and editor | **Add**, or tap the card → Edit tab | ✅ |
| Import .clock (full path) | **Import** (catalogue) | ✅ |
| Customise | **Edit**, or tap the card | ✅ |
| Use (select and save) | **Use** | ✅ |
| Duplicate (up to 24 variants) | **⋯ → Duplicate** sheet | ✅ |
| Remove (confirmation, keeps at least one face) | **⋯ → Remove from my faces**, then a confirmation sheet | ✅ |
| Show (full-screen trial) | ▶ button, or **⋯ → Show full screen** (animated zoom) | ✅ |
| Rename (in Options) | Also in **⋯ → Rename** | ✅ ➕ |
| — | Long press on the card → actions | ➕ |

## Edit (v2 faces)

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Style, Modules and Options modes (buttons) | Segmented control with a gliding pill, plus horizontal swipe | ✅ |
| Modules: + frames on the preview | Frames with a "+" badge | ✅ |
| Paginated picker of live-rendered complications | Scrolling sheet, every complication visible, flying frame | ✅ |
| Second-clock time zone (button at the bottom of the picker) | **Time zone: …** button in the sheet | ✅ |
| Style: Plein, Fin, Contour | **Bold, Thin, Outline** chips with a "12" specimen | ✅ |
| Appearance: Papier, Encre, Auto | **Paper, Ink, Auto** segments with sun, drop and auto icons | ✅ |
| Options: Rename, Export .clock | **Variant** group | ✅ |
| Orientation, time format, language, date format | **Time and date** group (choice sheets) | ✅ |
| Interface size | **Legibility** group (slider, − and +) | ✅ |
| A swipe never moves a complication | Unchanged (test `test_11`) | ✅ |

## Free editor (v1 imports)

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Interactive preview, drag an element | Unchanged, drag followed live | ✅ |
| Choose the element (6 elements) | **Element to edit** sheet | ✅ |
| Layout, Typography, Finish, Information, Images, Legibility sections | Six tiles, then a scrolling list with a Back button | ✅ |
| Every setting of those sections (`ui/controls.lua`) | Same keys: switches, sliders, choices and text fields | ✅ |
| Show | **Show** button (zoom) | ✅ |

## Sleep

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Clock on the sleep screen (enable, and restore the previous screen) | Main card with a switch | ✅ |
| Refresh: 1 min, 5 min, 15 min, Static | Segmented control: **1 min, 5 min, 10 min, 15 min, Static**, precision shown underneath | ✅ ➕ |
| Aura 2 priority wake-up (refused on other models) | **Wake-up** card | ✅ |
| Optimise for Aura 2 | **Optimise for Aura 2** | ✅ |
| Other settings: margin, reuse, full refresh, battery threshold, night pause start and end | **Advanced settings** in the same list | ✅ |
| — | RTC capability of the model (Kobo, Kindle through powerd, unavailable) | ➕ |

## Diagnostics

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Battery gauge, clock state, notice | Main card | ✅ |
| Updates, recoveries | Tiles with animated counters | ✅ |
| Next update | Card | ✅ |
| Technical details (paginated list) | Expanded inline in the scrolling list, with extra engine and RTC rows | ✅ ➕ |
| Export diagnostics | **Tools → Export diagnostics** | ✅ |
| Import / export a profile (JSON or old Lua) | **Tools → Profile** | ✅ |
| — | **Display** section: engine, profile, rates, settings, clean, retry | ➕ |

## General

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Draft, Cancel, Apply | **Draft** bar shown when there are changes | ✅ |
| Closing with a draft asks for confirmation | **Discard the draft?** sheet | ✅ |
| Status line | Short toasts | ✅ |
| Faces, Edit, Sleep, Diagnostics tabs | Tab bar with a gliding pill, sideways transitions | ✅ |
| Back key | Closes the sheet, then the sub-view, then the studio | ✅ |
| DPI-aware, landscape-aware, adjustable size | Unchanged (tests on 5 sizes and densities) | ✅ |
| Manual clock: a tap closes, a long press opens the studio | Unchanged | ✅ |
| **Atelier clock** option in KOReader's sleep screen menu | Unchanged | ✅ |
| Dispatcher actions (open the studio, show the clock) | Unchanged | ✅ |
| French interface | **English interface**; faces keep their own Clock language (English or French) | ➕ |
