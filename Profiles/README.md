# CRT Profile Settings

These tables list the fixed settings used by the current CRT profiles. Select
`Custom 1` or `Custom 2` in the OSD and enter the values from any row to use it
as a starting point for experimentation.

Star Wars and The Empire Strikes Back share the same profiles. Profiles resolve
independently for 240p, 480p/480i, 720p, and 1080p. The 720p settings apply to
every supported 720p refresh mode.

Grouped columns follow the OSD order:

- **Bloom:** Bloom Width / Bloom Curve
- **Halo:** Halo / Halo Spread

The Dot Scale column shows the effective size selected by `Auto` at each
resolution.

## 240p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Phosphor Decay | Color Space | Color Channels | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | Pixel | Bright | Tight / Mild | 0.25x / Wide 1 | Off | Off | RGB | Off |
| 80s Cruise Control | Pixel | Bright | Tight / Mild+ | 0.33x / Wide 1 | Off | Off | RGB | Off |
| 80s Overdrive | Pixel | Bright | Soft / Mild | 0.5x / Wide 2 | LUT C | Off | RGB | Off |
| Neon Fever Dream | Pixel | Bright | Tight / Strong | 0.75x / Wide 1 | LUT B | Off | RGB | Off |
| Pink Flamingo ESB | Pixel | Bright | Tight / Strong | 0.75x / Wide 1 | LUT B | Off | GRB | Off |

## 480p and 480i

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Phosphor Decay | Color Space | Color Channels | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2x | Bright | Tight / Mild | 0.25x / Wide 1 | Off | Off | RGB | Off |
| 80s Cruise Control | 2x | Bright | Tight / Mild+ | 0.33x / Wide 1 | Off | Off | RGB | Off |
| 80s Overdrive | 2x | Bright | Soft / Mild | 0.5x / Wide 2 | LUT C | Off | RGB | Off |
| Neon Fever Dream | 2x | Bright | Tight / Strong | 0.75x / Wide 1 | LUT B | Off | RGB | Off |
| Pink Flamingo ESB | 2x | Bright | Tight / Strong | 0.75x / Wide 1 | LUT B | Off | GRB | Off |

## 720p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Phosphor Decay | Color Space | Color Channels | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2x | Linear 2 | Tight / Mild+ | 0.33x / Wide 3 | Off | Off | RGB | Off |
| 80s Cruise Control | 2x | Linear 2 | Tight / Moderate | 0.5x / Wide 1 | Off | Amp709 | RGB | On |
| 80s Overdrive | 2x | Bright | Tight / Mod+ | 0.75x / Wide 3 | LUT C | Amp709 | RGB | On |
| Neon Fever Dream | 2x | Bright | Normal / Strong- | 1.25x / Wide 2 | LUT B | Off | RGB | Off |
| Pink Flamingo ESB | 2x | Bright | Normal / Strong- | 1.25x / Wide 2 | LUT B | Off | GRB | Off |

## 1080p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Phosphor Decay | Color Space | Color Channels | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2.5x | Linear 2 | Tight / Strong | 0.25x / Wide 1 | Off | Off | RGB | Off |
| 80s Cruise Control | 2.5x | Linear 2 | Soft / Mild | 0.5x / Wide 3 | Off | Amp709 | RGB | On |
| 80s Overdrive | 2.5x | Bright | Broad / Mild | 0.5x / Wide 3 | LUT C | Amp709 | RGB | On |
| Neon Fever Dream | 2.5x | Linear 2 | Wide / Strong | 1.5x / Wide 1 | LUT B | Off | RGB | On |
| Pink Flamingo ESB | 2.5x | Linear 2 | Wide / Strong | 1.5x / Wide 1 | LUT B | Off | GRB | On |

## Off and Custom Profiles

`A Touch of CRT` is selected after resetting the core settings.

`Off` selects the hard bypass. `Custom 1` and `Custom 2` are independent
user-defined slots and use their OSD values directly.
