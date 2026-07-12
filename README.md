# Star Wars + The Empire Strikes Back (Arcade, 1983 + 1985) for MiSTer FPGA

An FPGA implementation of Atari's classic color vector arcade games **Star Wars** and **The Empire Strikes Back** for the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Atari's 1983 Star Wars remains one of the most beloved arcade games ever made. With its glowing wire-frame Death Star trench, digitized voices of Obi-Wan and Darth Vader, and the iconic flight yoke controller, it was the closest thing to climbing into an X-wing cockpit — and for a generation of players, "Use the Force, Luke" still gives them chills.

## Support the Project
Hey, Videodr0me here! If you're having a blast with this core, consider supporting the project: [![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=flat-square&logo=buy-me-a-coffee)](https://buymeacoffee.com/Videodr0me)

---

## Original Hardware

The original Star Wars arcade machine (Atari part number 136021) is built from the following major components:

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main + Audio CPU** | Motorola MC6809E @ 1.5 MHz | Cavnex mc6809e Verilog core with AVMA/VMA wrapper |
| **Math Processor** | Custom TTL Mathbox (PROM-sequenced matrix processor, 74LS384 serial multiplier, 15-step restoring divider) | Fully modeled in `mathbox.sv` |
| **Vector Generator** | Atari Analog Vector Generator (AVG) with state machine PROM, 10-bit DACs, analog integrators | Cycle-exact digital AVG in `avg.vhd` based on schematics |
| **Sound** | 4× Atari C012294 POKEY + TI TMS5220 speech synthesizer | POKEY in VHDL + TMS5220 with variable rate (TMS5220C mode) |
| **Audio Filters** | TL084 quad op-amp low-pass filter + Reticon R5106 delay/reverb | Modeled in `audio_filter_tl084.sv` and `reticon_r5106.sv` |
| **Display** | Amplifone XY color vector monitor (RGB analog) | Ultra high performance raster vector renderer with CRT profile pipeline, bloom, halo, phosphor decay, slot mask, and color processing |
| **Controls** | Custom flight yoke with analog potentiometers (2-axis) | Mapped to MiSTer analog stick inputs, with digital fallback |
| **Non-volatile RAM** | 256 bytes battery-backed NOVRAM (high scores, settings) | Saved to MiSTer SD card via NVRAM system |

For those interested in the inner workings of the original arcade PCB, I have included my hand-verified transcription of the original AVG logic in the research folder. It is the exact blueprint I used to build the new AVG!

---
## Controls

Star Wars uses an analog flight yoke. The yoke's X and Y axes are mapped to the primary analog axes of your MiSTer controller (digital fallback input controls are available).

> **🕹️ Calibration Tip:** The game **auto-calibrates** to your controller's range. When you first start playing, **move the analog stick in a full circle through its extreme positions** — this lets the game learn your stick's full range of motion. You can do this at any time, but the stage select screen is the ideal moment. If you are using digital inputs, you must also calibrate by pressing up, down, left and right on the directional pad until the crosshair reaches the edges of the screen in all directions.

| Input | Function |
|---|---|
| **Analog Stick** | Move crosshairs (Pitch / Yaw) — proportional, recommended |
| **Fire (Button A)** | Fire lasers — also starts the game after inserting coins |
| **Shield (Button B)** | Shield button |
| **Aux Coin (Button Start)** | Auxiliary coin input (also used to navigate Test Mode menus) |
| **Coin L / Coin R** | Insert coins (mapped to R / L by default) |

If you do not have access to an analog control device, you can play with a digital D-Pad or keyboard using the core's built-in digital control option. You can configure its behavior in the **Input Controls** OSD menu:
- **Input**: Set to **Auto** to seamlessly engage digital control whenever you press a direction, or **Digital** to force it permanently.
- **Digital Sensitivity**: Adjusts how quickly the virtual yoke steers and re-centers.

> **Tip:** The original arcade machine has no "Start" button. After inserting a coin, pressing **Fire** on the yoke starts the game. An analog stick is strongly recommended for the best experience. You can also invert the **Y-Axis** in the Input Controls menu to accommodate unusual controllers or personal preference.


---

## Requirements

The CRT-style video effects pipeline uses MiSTer SDRAM and requires a 32MB SDRAM module or larger.

---

## Recommended MiSTer Video Settings

The MiSTer core automatically adapts to your chosen resolution and optimizes the video quality. It also features special modes for 15kHz and 31kHz CRT monitors.

For flat-panel displays, we highly recommend enabling the **HDR** option in `mister.ini`, if your monitor supports it. 1080p 60Hz is the primary recommendation for highest detail and smooth vector rendering. 720p 120Hz is also a good choice for smoother frame pacing on compatible displays. Both modes are well suited for **4K displays** because of the integer scaling ratio. The **Profile:** option in the OSD applies resolution-aware CRT effect settings.

Append these settings to your `mister.ini` file under the exact `[Star Wars]` header. Please ensure there is only one Star Wars core file in your MiSTer's search paths. Note that MiSTer filters and shadow masks are not needed and should be left blank (as shown below) to ensure best quality.

```ini
[Star Wars]
video_mode=8              ; 8 = 1080p or use 0 = 720p (enables 120Hz option)
vsync_adjust=2            ; 0 or 1 is also fine if you run into issues.
vscale_mode=0             ; Let the core's auto aspect ratio control scaling
hdmi_limited=0            ; Set to 1 if the image is too dark (e.g. on limited range TVs)
hdr=1                     ; HDR output — improves contrast/luminosity (Recommended!)
vrr_mode=0                ; Try 1 (or higher) if you have issues (e.g. 120Hz).
vfilter_default=          ; No filters needed! Leave blank.
vfilter_vertical_default= ; Override any global vertical filter
vfilter_scanlines_default=; Override any global scanline filter
```

> **Note:** The empty filter lines (`vfilter_default=` etc.) in the INI snippet ensure that any global scaler filters from your `[MiSTer]` section are overridden. Also disable any shadow masks as it might interfere with the new adaptive slot mask feature.

### 15kHz CRT / Pure Integer Scaling

If you are outputting to a 15kHz CRT (e.g. via direct_video or analog VGA), force the core's exact native resolution and aspect ratio:

```ini
[Star Wars]
video_mode=640,240,60 ; Standard MiSTer 15kHz resolution. You can experiment with others, but ensure width >= 640 and height is around 240 e.g. video_mode=640,44,64,88,240,3,2,17,13150,-hsync,-vsync
vscale_mode=4
vsync_adjust=0 ; You might want to try all three modes 0, 1 & 2
composite_sync=1 ; Try 1 = composite sync or 0 = separate sync
```
> **Tip:** For 31kHz monitors, use the same INI addition and set `video_mode=640,480,60`.

---

## Update Notes

If you are updating from an older release, delete the MiSTer config files for this core before first launch. Typically these files are found under `/media/fat/config/`, but your setup may vary.

---

## OSD Options

### Display

| Option | Description |
|---|---|
| **Aspect Ratio** | **Optimized** auto-detects the HDMI resolution and picks the intended core aspect. **Stretched** fills the display. **Pixel Perfect** forces direct pixel mapping. |
| **120Hz (720p only)** | Enables ~120Hz output when using a 720p video mode. Useful for smoother frame pacing on compatible displays. |
| **Buffer Mode** | Selects how the renderer swaps completed vector frames. The default mode is recommended. |
| **Profile:** | Selects from five video presets and two additional custom slots. **Custom 1** and **Custom 2** expose the full advanced video control set. |

### Video Profiles

| Profile | Description |
|---|---|
| **Off** | Direct output path bypassing the CRT effects filter pipeline. |
| **A Touch of CRT** | Subtle CRT halo and bloom for modern anti-aliased vector drawing. |
| **80s Cruise Control** | Amplifone color, authentic slot mask, richer halos, and more bloom. |
| **80s Overdrive** | Overdriven CRT glow with stronger phosphor decay; results vary with your display and settings. |
| **Neon Fever Dream** | Stylized high-energy CRT look with excessive flashing bright lights. |
| **Pink Flamingo ESB** | Channel-swapped fun variant, especially suited for Empire Strikes Back. |
| **Custom 1 / Custom 2** | Two independent user-configurable slots exposing the full set of advanced controls. |

> **Warning:** Neon Fever Dream and Pink Flamingo ESB can produce excessive flashing bright lights.

### Custom Profile Controls

When **Custom 1** or **Custom 2** is selected, the OSD exposes the full set of advanced video controls:

| Option | Description |
|---|---|
| **Dot Scale** | Controls the apparent size of vector dots (e.g. stars): Auto, Pixel, 2x, or 2.5x. |
| **Tone Mapping** | Controls Z-intensity mapping: Linear 1, Linear 2, Bright, or Off. |
| **Bloom Width / Bloom Curve** | Controls local bloom around bright vector pixels. |
| **Halo / Halo Spread** | Controls the broad CRT glow around bright vectors and dense scenes. |
| **Phosphor Decay** | Selects the afterglow lookup table: Off, LUT A, LUT B, or LUT C. |
| **Color Space** | Selects processing that more accurately reproduces the Amplifone blue hues. |
| **Color Channels** | Selects RGB channel order, B/W, or Negative. |
| **Slot Mask** | Enables the CRT-style adaptive slot mask. |

### Cabinet Audio Hardware

The original Star Wars arcade cabinet features analog audio processing that goes beyond simple DAC output. This core models filter, delay, and reverb stages, giving you an authentic stereo audio rendition like never before:

| Option | Default | Description |
|---|---|---|
| **TL 084 Filter** | On | Models the original TI TL084 quad op-amp low-pass filter on the audio output board. |
| **Reticon Del/Rev** | On | Models the Reticon R5106 analog delay line used in the original cabinet for spatial reverb effects. Adds a subtle authentic stereo "cockpit echo" to explosions and speech. |

> **Tip:** For the most authentic arcade sound experience, keep both options **On**. Turning the TL 084 Filter off yields a more modern Hi-Fi flavour of the audio.

---

## Game Setup — Use Test Mode, Not DIPs

The recommended way to change game settings is NOT through the DIP switches, but through the game's built-in **Test Mode menu**, just like arcade operators did on the original machine:

### How to Access Test Mode

1. Wait for the demo loop, then open the MiSTer OSD (F12)
2. Go to **DIP Settings** → set **Test Mode** to **On**
3. Close the OSD — the game enters the game setup / diagnostic screen
4. Use the **flight yoke** (analog stick) to navigate the on-screen menu
5. Press **Fire** to select options
6. Configure difficulty, coinage, bonus shields, and other game parameters
7. The game saves your settings to NVRAM automatically
8. Set **Test Mode** back to **Off** in the OSD to return to normal gameplay

Settings changed through Test Mode are preserved in NVRAM alongside your high scores. Do not forget to save NVRAM; Auto Save runs when entering the F12 menu.
The DIP switches in the OSD can configure starting shields, difficulty, coinage, and other game parameters. However, **changing DIPs requires clearing NVRAM**, which **erases all saved high scores**.
> **Note:** Star Wars only saves the top three high scores. ESB saves the top 10.

---

## ROMs

```
                                *** Attention ***

ROMs are not included. To use this arcade core, provide the correct ROM sets; see the MRA files for the required versions.

Quick reference for folders and file placement on your MiSTer SD card:

/_Arcade/Star Wars (Rev 2).mra
/_Arcade/Empire Strikes Back.mra
/_Arcade/cores/Arcade-StarWars.rbf
/games/mame/starwars.zip
/games/mame/esb.zip
```

> **Note:** The core file can also simply be named `StarWars.rbf` (dropping the `Arcade-` prefix). The MiSTer framework will automatically find and load it using either name based on the updated MRA definitions.

---

## Compilation

The project uses **Quartus Prime Lite** targeting the **Cyclone V** on the Terasic DE10-Nano.

1. Open `Arcade-StarWars.qpf` in Quartus
2. Run the full compilation flow (Analysis → Fitter → Assembler → Timing)
3. The output `Arcade-StarWars.rbf` is generated in `output_files/`

The `sys/` directory contains the standard MiSTer framework. All core-specific RTL is in `rtl/`.

---

## Credits & Acknowledgments

- **Star Wars (Arcade):** Mike Hally (project lead), Greg Rivera & Norm Avellar (programming), Jed Margolin (hardware engineering), Ed Rotberg (original concept) — Atari, 1983
- **Empire Strikes Back (Arcade):** Mike Hally (project lead), Greg Rivera & Norm Avellar (programming), Rob Row (technician), Dave Ralston (artist), Brad Fuller (sound effects) — Atari, 1985
- **Initial FPGA Foundation:** Jeroen Domburg (Black Widow MiSTer core)
- **6809 CPU Core:** Greg Miller (Cavnex mc6809e)
- **MiSTer Platform:** Sorgelig and the MiSTer community
- **Slapstick/Empire Strikes Back support:** derpyder

---

## License

This project is provided for educational and personal use. See individual source files for their respective licenses.
