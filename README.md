# Time & Day Clock

An ultra-low-power, highly-customizable screensaver and clock widget for KOReader on e-ink devices.

> [!NOTE]
> This plugin is a **fork of `dtdisplay.koplugin`** with massive battery optimizations, custom watch face rendering improvements, and layout bug fixes.

> [!WARNING]
> This project is currently in **Beta** and may be unstable. Use at your own risk.

---

## 📸 Screenshots

Here is the clock plugin in action:

| Interactive Visual Customizer | Word Clock Face |
| :---: | :---: |
| ![Word Clock](sreenshot_demo/word_clock_view.png) | ![Analog Clock](sreenshot_demo/analog_clock_layout.png) |

| full screen clock | customizable appearance |
| :---: | :---: |
| ![Visual Customizer](sreenshot_demo/customizer_view.png) | ![Demo 1](sreenshot_demo/demo_1.png) |

---

## ✨ Key Features

- **5 Watch Face Styles**:
  - `Classic`: Clean digital clock (Hour:Minute) with date and battery.
  - `Fullscreen`: Giant stacked digits (Hour on top, Minute below) that fill the screen.
  - `Outlined`: Digital clock text with a customizable outline (great for overlaying on complex PNG wallpapers).
  - `Analog`: A highly detailed analog clock face with ticking markers, hour/minute hands, and a center pivot.
  - `Word Clock`: Time spelled out in French words (e.g. *"Il est dix heures trente-cinq"*).
- **Interactive Visual Customizer**: Long-press anywhere on the clock screen to open a graphical dashboard. Customize layout, styles, sizes, rotation, fonts, night mode, separators, and borders instantly without restarting KOReader.
- **Dynamic Auto-Layout**: Automatically stacks all visible widgets (date, clock, battery) vertically. The layout automatically detects the size of multi-line widgets (like the Word Clock) and pads them to avoid overlap.
- **Decorative Separators & Borders**: Add decorative lines, dots, diamonds, or ornamental separator dividers and corner frames.
- **DPI-Scaled Graphics**: All interface elements are scaled dynamically relative to your screen size for a gorgeous, crisp presentation on both low and high-DPI displays.

---

## ⚡ Energy Optimization (Battery Lifespan)

This plugin has been heavily engineered to draw the absolute minimum amount of power from your e-reader:

1. **RTC Deep Sleep Coordination**: The clock wakes the device via RTC alarm every minute. Once awake, it renders the screen, schedules the next alarm, and instantly releases the wake lock, forcing the CPU to go back into deep sleep (`mem` state) within **less than 0.5 seconds**. The CPU is completely powered down 99% of the time.
2. **Sprite Cache Rendering**: Instead of rendering vector fonts from scratch every minute (which is CPU intensive), individual character glyphs are vector-traced only once when they first appear and cached as tiny sprites. Every subsequent update is drawn via raw memory blitting, reducing CPU load.
3. **No Redundant Driver Manipulations**: The plugin relies entirely on the Linux kernel and KOReader's native suspend loop to handle the touchscreen hardware shutdown. It does not attempt to write manually to `/sys/` touch files or close device streams logic, preventing race conditions that cause touchscreen freezes on wake.

---

## 📱 Compatibility

- **Kobo Aura 2 (tested and verified)**: The plugin was originally developed and thoroughly tested on a Kobo Aura 2.
- **Kindles / Other Kobos (untested)**: The RTC wakeup and power loops should work on Kindle but have **not** been tested. I CANNOT guarantee that deep sleep RTC wakeups function correctly on Kindle devices.

---

## ⚙️ Installation

1. Connect your e-reader to your computer via USB.
2. Navigate to your device's KOReader directory (usually `koreader/` on the root of Kobo storage).
3. Open the `plugins/` directory.
4. Copy the `time_and_day_clock.koplugin` folder from this repository directly into the `plugins/` directory.
   - The path should look like: `koreader/plugins/time_and_day_clock.koplugin/`
5. Disconnect your e-reader and start KOReader.
6. Enable the screensaver:
   - Go to **Settings (gear icon)** > **Screen** > **Screensaver** > **Screensaver type** and select **Show clock on sleep screen** .
7. Wake up the clock:
   - Tap **Settings** > **Plugins** > **more tools** > **Time & Day Clock** to open the options and launch the clock manually.
   - Long press on the screen when the clock is visible to configure it via the **Visual Customizer**.
