# Atelier Clock

**0.3.0 "Fluid", 19 November 2026.** Ten `.clock` faces, a collection, a complication editor, and an animated full-screen studio built for the **Fluid Ink 6.5** engine.

## Fluid display

The studio composes its frames in 8-bit greyscale from layers kept in memory, then hands them to the built-in Fluid Ink engine (`engine/fluidink`):

- **Kobo Aura Edition 2 v1**: Fluid Ink v6, **Pulses 2**, **Throughput** profile (queue 1, Bayer 8×8, no gamma), 30 fps target. In Fluid Ink's own French labels these are *Impulsions 2* and *Débit*.
  - The pulse profile needs **your own** copy of `factory-reference.bin` in `engine/fluidink/`. It is not redistributed.
  - Without it, or if the kernel refuses the pulses, the plugin switches to v6 without pulses.
- **Other Fluid Ink-compatible readers** (Aura 2 v2, Aura H2O 2, Glo HD, Aura One, Clara HD, Kindle PW2/PW3/Voyage): Fluid Ink v6 without pulses, A2 while moving and DU at rest.
- **Everywhere else**, or when the engine check fails: classic KOReader refresh, with the same screens and each animation replaced by its final state.

The engine is checked in RAM in a separate process before any use. While the studio is open, it is the only thing writing to the panel:

- For text entry, it stops, restores the original waveform table, then resumes. The first frame after resuming may flash (GC16).
- Before every sleep, it stops synchronously. The sleep-screen clock never uses Fluid Ink.
- In landscape or night mode, the studio stays on the classic display.

**Diagnostics → Display** shows the active engine, its profile and live targets and scans per second. It also holds the engine settings:

| Setting | Values |
|---|---|
| Display engine | Automatic, Fluid or Classic |
| Target frame rate | 30, 45 or 60 Hz |
| Clean at rest | On or off |
| Animations | Full or Reduced |

From the same section you can clean the screen or retry the engine. The counters do not measure optical cadence; check that with a camera on the panel.

## Wake-up by reader

| Reader | How it wakes | Notes |
|---|---|---|
| **Kobo**: the seven Fluid Ink-compatible models | Hardware RTC through `WakeupMgr` | Suspend handled by KOReader. |
| **Kindle** Paperwhite 2/3 and Voyage | `WakeupMgr` with `mockrtc`, through powerd | KOReader must own the sleep screen. powerd suspends the reader itself. A guard catches the minute if the reader stayed awake, or if a past alarm was dropped. About 15 s precision, so 5 minutes is recommended. |
| **No programmable wake-up** | None | The clock freezes when the reader sleeps, and says so. |

## Enabling the Aura 2 profile

After updating, open **Sleep → Optimise for Aura 2 → Apply**. The button turns on:

- fast handling of the clock's own wake-ups;
- conditional reuse of the suspend preparation;
- a 0.1 s margin after the display finishes.

It does not change your refresh profile (keep **1 minute**), the night pause or the configured full refresh.

Reuse requires a compatible native API, a validated previous sleep, a reliable screen wait, Wi-Fi off, no charging, and the `state-extended` kernel flag still at 1. These conditions are checked again at the moment of reuse.

When the minute RTC mode is confirmed, native `standby` with its zero flag is used instead. In every other case, the full native preparation runs. The option can be turned off in the other power settings.

A too short return disables reuse of the deep preparation. On a confirmed FP9928 model, minute RTC standby can take over; if that mode fails, the native fallback is kept for the session. Other alarms stay in the native queue, and a user wake-up cancels the deferred request. The plugin never changes the CPU governor, kernel, drivers or sysfs state directly.

## Installing or updating

1. Quit KOReader completely.
2. **Replace the whole** `atelierclock.koplugin` folder in KOReader's `plugins` folder with the one from this archive. Do not merge folders: that would keep the old faces. On many Kobos the path is `.adds/koreader/plugins/atelierclock.koplugin`.
3. **Keep `settings/atelierclock`**: it holds your preferences and imported faces. RTC, full refresh, orientation and interface size settings are kept.
4. Eject the reader, restart KOReader and open **Tools → More tools → Atelier Clock**. Enable the plugin in the plugin manager if needed.
5. In **Sleep**, turn the clock on. The **Atelier clock** option is also in KOReader's own sleep screen menu, in both the reader and the file browser.

On the first launch of the collection, the currently available face is added to "My faces". If your old model is no longer bundled, **Totem** takes its place. Old settings are not erased.

Free placement, custom fonts and per-image backgrounds apply to imported `.clock` v1 faces. v2 compositions use their own styles and slots.

## Browsing and customising

| Screen | What you can do |
|---|---|
| **Faces → My faces** | A carousel you drag with your finger; it keeps its momentum, then snaps to a face, with neighbours peeking in from the sides. Browsing never changes the active clock. **Use** selects and saves. **▶** runs the full-screen trial, zooming in from the preview. |
| **⋯** (or a long press on the card) | Opens a sheet: **Duplicate**, **Rename**, **Show full screen**, **Remove from my faces**. You can have up to 24 variants; removing one keeps its model in the catalogue. |
| **Catalogue** | The ten models and your imports. **Add** creates a personal variant and opens the editor. **Import** takes the full path of a `.clock` file. |
| **Edit → Style** | Bold, Thin or Outline depending on the face, and Paper, Ink or Auto appearance. |
| **Edit → Modules** | Tap a **+** frame. A sheet rises with each compatible complication rendered for real; the content you choose flies to its slot. |
| **Edit → Options** | Name the variant, export a `.clock`, choose orientation, time format, clock language, date format and interface size. |

Changes stay in a **draft**:

- The *Draft · Cancel · Apply* bar appears only when there is something to apply.
- Closing the studio with a draft asks for confirmation.

Lists scroll with momentum and an elastic edge. A horizontal swipe changes tab, or mode inside Edit.

The free editor remains available for v1 imports: drag elements on the preview, then go through the six settings sections.

Previews show the time at the moment they are drawn. The interface takes the DPI into account, reflows for landscape and compact screens, and can be enlarged.

## The ten bundled faces

| File | Original composition |
|---|---|
| `totem.clock` | Two tiers of monumental digits; date and battery ring. |
| `duplex.clock` | Two contrasting panels and two rectangular complications. |
| `index.clock` | 24-hour ruler, off-centre time, two cartouches. |
| `halo.clock` | Fine hands and ticks, two customisable rings. |
| `journal.clock` | Large time and a real monthly calendar, today framed. |
| `lisiere.clock` | Ink landscape, understated time and a round seal. |
| `mosaique.clock` | One large and two small modules around the time. |
| `octant.clock` | Current-hour medallion and a minute arc. |
| `typo.clock` | Time written in words, a literary composition. |
| `signal.clock` | Geometric seven-segment display, without animation. |

Each model has a real portrait layout **and a separate landscape layout**. The ten `.clock` files are DEFLATE ZIPs with JSON, original PNG textures and a preview rendered by the Lua engine. No time is baked into the textures.

Text on the faces (dates, words, complication titles, status notes) follows the **Clock language** option: English by default, or French.

## Offline complications

The seven available contents are **Empty**, **Date**, **Battery**, **Day**, **Week**, **World clock** and **Reading**. They come in three families (line, ring and rectangle) and adapt to the space they are given.

- The calendar is computed locally, with month lengths and leap years.
- Day is an indicative progress bar updated every quarter of an hour; the Index ruler moves every five minutes. The main time keeps following the chosen RTC profile.
- The bundled time zones are UTC, Paris, London, New York and Tokyo, with IANA transitions 1970–2100. To change city, reopen the world clock module and tap the time zone button at the bottom of the sheet.
- Reading shows the title and percentage KOReader recorded when the scene started. This reading snapshot creates no task and no metadata read every minute. When it is unavailable, the module shows a dash and an explicit hint.
- An unknown battery level stays shown as unknown.

No fake weather, network connection or sync task is created for these modules.

## Importing and exporting

| Action | Where | Notes |
|---|---|---|
| Import a face | **Catalogue → Import** | Takes the full path of a file. v1 files remain readable. A model identifier that is already installed is refused; to make several visual versions of the same model, use **Duplicate**. |
| Export a face | **Edit → Options → Export as .clock** | Choose a new path; the suggested one is `settings/atelierclock/exports/…`. The export holds the composition, textures, a preview of the variant and its style and complication preset. It is validated before being written, can be imported again under a new identifier, and never overwrites an existing file. Personal RTC settings are not included. New exports are v2. |
| Import or export a settings profile | **Diagnostics → Tools → Profile** | An existing JSON path imports, a new path exports. Importing old Lua files only parses literal tables and never executes code. |

## Rendering and power

The v2 engine keeps the background and already-drawn elements in memory. Date, calendar, decoration and reading progress are not recomputed every minute. Totem, Duplex and Signal draw hours and minutes separately. Analogue ticks are cached, and both old and new hand positions are included in the area to clear.

**Refresh windows**

- Disjoint windows stay separate up to four; beyond that, the plugin requests one bounding window.
- For ordinary digits and hands, windows are tightened around the old and new strokes.
- Configured full refreshes and KOReader's safeguards are kept.
- Regular sleep refreshes use `ui` mode, so they no longer consume the reader's page counter, which could trigger extra full refreshes unrelated to the face setting.
- The battery reading needed for the stop threshold is reused by the complications during the same wake-up.

The simulated 60-minute sequence at 758×1024 was recomputed with the adaptive scan. **Requested windows are not a measure of battery savings.** Initial paints and full refreshes are excluded from that comparison and remain active. KOReader and the controller may align or promote refreshes. Full figures and limits are in `docs/RENDER_MEASUREMENTS.json`.

**Suspend**

- At one minute, the number of alarms is unchanged.
- The first suspend keeps its full native preparation.
- After a wake-up owned by the clock, the plugin can skip repeating it: it calls the native `_doSuspend` phase after the refresh has finished, and only if the preparation flag is still set.
- Native disk sync, `mem` suspend and error handling still run.

These graphical optimisations alone cannot promise a few battery points per week.

**Refresh profiles and safeguards**

- **Sleep** offers the 1, 5, 10 and 15-minute and static profiles. The clock shows a visible note when the time is approximate or frozen.
- The night pause suspends updates until the resume hour. These trade-offs are never enabled silently.
- The battery threshold stops wake-ups for the session.

The priority wake-up / fast RTC option stays limited to recognised Aura 2 models (`Kobo_star`, `Kobo_star_r2`). It is off by default on a fresh installation, and an existing preference is kept. It uses KOReader's native check 0.2 s after a deadline owned by the plugin, while other alarms, grace periods and suspend safeguards are respected. Without it, the native guard can wait about 15 seconds.

## Checking on the reader

**Diagnostics → Tools → Technical details** shows, for the last session:

- total sleep and its share of the session;
- the delay between wake-up and the next sleep request;
- reused preparations, and the reason for any return to native mode;
- render CPU time (which is not the total awake time), requested refresh area, alarm delay and recoveries;
- the battery level over the session;
- the display engine and the RTC capability.

**Previous suspend** is decoded through `ui/time`: the `2787663 s` of beta 3 were really **2.787663 seconds**. The same conversion applies to the sleep validation threshold, so a suspend of a few microseconds is no longer mistaken for a second. Battery figures are gauge points, not a calibrated electrical measurement.

For a meaningful comparison with a previous trial:

- keep the same interval, RTC option and frontlight;
- start at a comparable charge and note the start and end times;
- **Halo** is a good test thanks to its small hand rectangle; also check for residual ghosting after several hours.

The total is frozen when the session ends, so time spent reading the diagnostics is not added to that session's awake time. The JSON report also holds the detected capabilities, the kernel version and the last 120 sleep samples kept in RAM. A manual export writes `settings/atelierclock/diagnostic.json`; a normal end of session writes `settings/atelierclock/last-session.json` once.

The manual clock closes on a tap; a long press opens the studio. It does not block auto-suspend. During real Kobo sleep, use the power button or the sleep cover: touch is not necessarily powered. Power-off and restart screens stay under KOReader's control.

To remove the plugin, first turn the clock off in **Sleep**, quit KOReader, then delete its folder. If the folder is already gone, choose a standard sleep screen in KOReader.

## Further reading

- Format and limits: `docs/CLOCK_FORMAT.md`.
- Tests and hardware limits: `docs/VALIDATION.md` (French).
- Design references: `docs/DESIGN_RESEARCH.md`.
