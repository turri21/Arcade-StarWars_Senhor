# Star Wars + The Empire Strikes Back (Arcade, 1983 + 1985) for MiSTer FPGA

An FPGA implementation of Atari's classic color vector arcade games **Star Wars** and **The Empire Strikes Back** for the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Atari's 1983 Star Wars remains one of the most beloved arcade games ever made. With its glowing wire-frame Death Star trench, digitized voices of Obi-Wan and Darth Vader, and the iconic flight yoke controller, it was the closest thing to climbing into an X-wing cockpit — and for a generation of players, "Use the Force, Luke" still gives them chills.

Atari's 1985 successor, **The Empire Strikes Back**, drops you into the Battle of Hoth in a snowspeeder, where you hunt probe droids and bring down AT-AT walkers with a limited supply of tow cables. The action then shifts to the Millennium Falcon for a running battle with TIE fighters and a desperate flight through the asteroid field, all under Darth Vader's ominous pull toward the dark side.

## Support the Project
Hey, Videodr0me here! If you're having a blast with this core, consider supporting the project: [![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=flat-square&logo=buy-me-a-coffee)](https://buymeacoffee.com/Videodr0me)

---

## Original Hardware

The original Star Wars arcade machine (Atari part number 136021) and the 1985 conversion kit for The Empire Strikes Back (Atari part number 136031) use the following major components:

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main + Audio CPU** | Motorola MC6809E @ 1.5 MHz | Cavnex mc6809e Verilog core with AVMA/VMA wrapper |
| **Math Processor** | Custom TTL Mathbox (PROM-sequenced matrix processor, 74LS384 serial multiplier, 15-step restoring divider) | Fully modeled in `mathbox.sv` |
| **Vector Generator** | Atari Analog Vector Generator (AVG) with state machine PROM, 10-bit DACs, analog integrators | Cycle-exact digital AVG in `avg.vhd` based on schematics |
| **Sound** | 4× Atari C012294 POKEY + TI TMS5220 speech synthesizer | POKEY in VHDL + TMS5220 with variable rate (TMS5220C mode) |
| **Audio Filters** | TL084 quad op-amp low-pass filter + Reticon R5106 delay/reverb | Modeled in `audio_filter_tl084.sv` and `reticon_r5106.sv` |
| **Display** | Amplifone XY color vector monitor (RGB analog) | Ultra high performance raster vector renderer with CRT profile pipeline, bloom, halo, phosphor decay, slot mask, and color processing |
| **Controls** | Custom flight yoke with analog potentiometers (2-axis) | Analog stick, trackball/mouse, and digital control modes |
| **Non-volatile RAM** | 256x4-bit X2212 NOVRAM (high scores, settings) | Saved to MiSTer SD card via NVRAM system |

For those interested in the inner workings of the original arcade PCB, I have included my hand-verified transcription of the original AVG logic in the research folder. It is the exact blueprint I used to build the new AVG!

---
## Controls

Star Wars uses an analog flight yoke. **Analog Stick** is the default and
recommended input, while the core also supports trackball/mouse and digital
control.

> **🕹️ Calibration Tip:** The game **auto-calibrates** to the available yoke
> range. With an analog stick, move it through its full range after starting.
> With mouse, trackball, or digital control, steer once to all four limits.
> The stage select screen is a convenient place to do this.

| Input | Function |
|---|---|
| **Analog Stick** | Move crosshairs (Pitch / Yaw) — proportional, recommended |
| **Fire L / Fire R (A / Y)** | Fire lasers; either fire control also starts the game after inserting coins. |
| **Shield L / Shield R (B / Z)** | Original cabinet shield buttons; function as additional fire buttons. |
| **Aux Coin (Start)** | Auxiliary coin input; also advances Test Mode menus. |
| **Coin L / Coin R (R / L)** | Insert coins. |

The **Input Controls** menu provides these choices:

| Option | Behavior |
|---|---|
| **Analog Stick** | Direct proportional control from the primary analog stick. |
| **Trackball / Mouse** | Steer with a trackball or mouse. |
| **Digital Centering** | Directions move the yoke; releasing them returns it to center. |
| **Digital Relative** | Directions move the yoke and it holds its last position when released. |
| **Auto** | Starts with the analog stick and switches to whichever supported input moves. |
| **Sensitivity** | Scales analog, trackball/mouse, and digital movement from 0.125x to 2.0x. |
| **Y-Axis** | Selects normal or inverted vertical control. |

> **Tip:** The original arcade machine has no "Start" button. After inserting a coin, pressing **Fire** on the yoke starts the game. An analog stick is strongly recommended for the best experience. You can also invert the **Y-Axis** and adjust **Sensitivity** to suit your controller and preferences.


---

## Requirements

The CRT-style video effects pipeline uses MiSTer SDRAM and requires a 32MB SDRAM module or larger.

---

## Recommended MiSTer Video Settings

The renderer supports 240p, 480i, 480p, 720p, and 1080p. **1080p is
recommended** with `hdr=1` for the highest vector detail and dynamic range.
Compatible 720p displays can also use the optional 120 Hz mode.

For high-resolution flat-panel output, place the following settings under the
exact `[Star Wars]` header at the end of `MiSTer.ini`. The empty filter and
mask entries prevent MiSTer's scaler effects from altering the core's own CRT
pipeline.

```ini
[Star Wars]
video_mode=8   ; 8 = 1080p, 0 = 720p
hdr=1
vsync_adjust=1 ; use 1 or 2 for 120 Hz output
vscale_mode=0
hdmi_limited=0 ; use 1 for limited-range displays (or if output is too dark)
vfilter_default=
vfilter_vertical_default=
vfilter_scanlines_default=
shmask_default=
shmask_mode_default=0
```

### CRT and Direct Video Output

#### CRT Output

> **Required for CRT output:** Add all three entries below to the `[Star Wars]`
> section of `MiSTer.ini`. These settings provide the best image quality and
> are required for 480i output.

```ini
[Star Wars]
video_mode=720,240,60
vga_scaler=0
forced_scandoubler=0
```

Place this section at the end of `MiSTer.ini` so it overrides earlier global
settings. Under **Video Timing & Geometry**, **15 kHz Format** selects 480i or
240p, with 480i used by default. Do not use `vga_scaler=1` or custom modelines.
For a 31 kHz CRT, use `video_mode=720,480,60` instead.

#### Direct Video

For Direct Video, use the same settings above and additionally add
`direct_video=1` to the `[Star Wars]` section of `MiSTer.ini`. **Direct Video
Scan Rate** then selects 15 kHz or 31 kHz output, while **15 kHz Format**
selects 480i or 240p at 15 kHz.

---

## Update Notes

If you are updating from an older release, delete the MiSTer config files for this core before first launch. Typically these files are found under `/media/fat/config/`, but your setup may vary.

---

## OSD Options

### Video Timing & Geometry

| Option | Description |
|---|---|
| **Orientation** | Provides all eight unique rotation and mirroring combinations. |
| **Zoom** | **Normal** preserves the released framing. **Wide** shows additional space around the game image. |
| **Buffer Mode** | Selects how the renderer swaps completed vector frames. The default mode is recommended. |
| **120Hz (720p only)** | Enables ~120Hz output when using a 720p video mode. Useful for smoother frame pacing on compatible displays. |
| **Direct Video Scan Rate** | Selects 15 kHz or 31 kHz output when Direct Video is active. |
| **15 kHz Format** | Selects 480i or 240p in the 15 kHz output bracket. 480i is the default. |
| **CRT Vertical Position** | Moves 240p, 480p, or 480i output vertically. Positive values move the picture down. |
| **Aspect Ratio** | **Optimized** auto-detects the HDMI resolution and picks the intended core aspect. **Stretched** fills the display. **Pixel Perfect** forces direct pixel mapping. |

### Video Profiles

| Profile | Description |
|---|---|
| **A Touch of CRT** | Default. Subtle CRT halo and bloom for modern anti-aliased vector drawing. |
| **80s Cruise Control** | Amplifone color, authentic slot mask, richer halos, and more bloom. |
| **80s Overdrive** | Overdriven CRT glow with stronger phosphor decay; results vary with your display and settings. |
| **Neon Fever Dream** | Stylized high-energy CRT look with excessive flashing bright lights. |
| **Pink Flamingo ESB** | Channel-swapped fun variant, especially suited for Empire Strikes Back. |
| **Custom 1 / Custom 2** | Two independent user-configurable slots exposing the full set of advanced controls. |
| **Off** | Direct output path bypassing the CRT effects filter pipeline. |

See [CRT Profile Settings](Profiles/README.md) for the exact settings used at
each resolution.

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
