# WhatsApp Status compression — design

**Status:** awaiting the owner's approval. Compress video first; the editor's export gets the same
rule once this is confirmed on a device (the export-menu switch is already chosen: a
"WhatsApp Status" switch under Resolution and Frame rate that overrides both).

## Why

The owner's main use for compression is posting to WhatsApp Status without WhatsApp turning the
video soft. Evidence the owner gathered (files in `Slimshot workspace/videos`, read with a small
MP4 reader):

| | Screen recording (source) | SlimShot export — **blurred** on Status | Instagram download — **clear** on Status |
| :--- | :--- | :--- | :--- |
| Resolution | 720×1612 | 1080×1920 | 720×1280 |
| Frame rate | variable, mode 45 | constant 30 | constant 30 |
| Video kbps (average / busiest 1 s) | 2437 / 12962 | 1061 / 3145 | 426 / 1366 |
| Encoding | H.264 Main 3.1 | H.264 High 4.0 | H.264 High 3.1 |
| Audio | none | AAC 129 kbps 44.1 kHz | AAC 60 kbps 44.1 kHz |
| Colour / rotation | BT.709 SDR / none | same | same |

The clear file was smaller and lower in bitrate. The difference that matters is **shape**:
WhatsApp keeps something like 720×1280 and resizes anything larger itself, quickly and at a low
bitrate, which is the blur. The SlimShot file had also been *enlarged* from a 720-wide source to
1080 before WhatsApp shrank it again. So the job is: **hand WhatsApp a file already in the shape
it keeps, encoded cleanly**, so it either posts it as it is or has almost nothing to redo.

WhatsApp does not publish its limits and changes them between versions. The shape above comes
from the evidence; the **bitrate ceiling comes from a measurement** (below), not a guess.

## Goals

- One switch on Compress video, **WhatsApp Status**, whose result stays clear when posted to
  Status with WhatsApp's HD option on — as clear as the Instagram round trip.
- A file that is already status-ready is handed back **untouched**: no generation loss.
- The numbers that depend on WhatsApp (bitrate ceiling) are set by measuring what WhatsApp
  actually delivers, and live in one place so they can be retuned.

## Non-goals

- **The editor's export.** Next, after this is device-confirmed, with the same rule.
- **Splitting long videos** into status-length parts — the owner's call: no splitting. A video
  longer than WhatsApp allows is left for WhatsApp to cut.
- Photos. The photo compressor has no WhatsApp option and gets none here.
- Guaranteeing WhatsApp never re-encodes. It is not ours to control; we control how little it
  has to do and how clean its input is.

## Anti-goals (a failure even if it "works")

- A result softer than the Instagram round trip of the same video.
- Upscaling anything. A 480p source stays 480p.
- Washed-out, grey colour from HDR footage.
- A switch that does half the job silently — what the current `whatsAppOptimize` is: it scales
  by **width** only (a portrait 1080×1920 stays 1080×1920), forces Baseline profile, rides the
  preset's `superfast`/`ultrafast` settings, and has no bitrate ceiling.

## The file the switch makes

All of it decided from one probe of the input, as a pure plan (see Testing).

| | Rule |
| :--- | :--- |
| **Size** | Fit inside 720×1280 (portrait) or 1280×720 (landscape): short side ≤ 720 **and** long side ≤ 1280, aspect kept, both sides even, **never larger than the source**. A square fits 720×720. Lanczos scaling, square pixels out. |
| **Frame rate** | Constant. 60 → 30, 50 → 25, otherwise the source's rate capped at 30. A variable-rate source (screen recordings are) becomes constant. |
| **Video** | H.264 **High**, level **3.1** (720×1280@30 is exactly level 3.1's frame-size limit), 8-bit 4:2:0, tagged BT.709. |
| **HDR** | A source whose transfer is PQ (`smpte2084`) or HLG (`arib-std-b67`) is tone-mapped to SDR BT.709 (`zscale` + `tonemap`, the build has zimg) before anything else. A 10-bit SDR source is simply converted to 8-bit. |
| **Noise** | A light temporal-spatial denoise (`hqdn3d`, mild) before scaling, so sensor grain does not eat the bitrate and turn into blocks. Strength is checked in the measurement (one variant without). |
| **Bitrate** | Quality-targeted with a ceiling: x264 CRF (start at 21) with `maxrate` = the ceiling and `bufsize` = twice it. Easy content (an app screen) comes out small like Instagram's; hard content (camera, motion) rides the ceiling. Ceiling `kStatusMaxVideoKbps`, **provisional 2000**, final from the measurement. |
| **Encoder speed** | x264 `medium` (the presets use `superfast`/`ultrafast`). Time on the Infinix is measured; if a one-minute clip takes much over two minutes, step to `fast`. |
| **Audio** | AAC-LC 128 kbps, 44.1 kHz; more than two channels are downmixed to stereo, mono stays mono, no track stays no track. |
| **Container** | MP4 with the index first (`+faststart`), rotation applied to the pixels (no rotation flag left), the existing metadata switch respected. |

**Already status-ready → no re-encode.** Ready means: H.264 video and AAC audio (or none), size
already inside the fit, frame rate ≤ 30, SDR 8-bit, no rotation flag, and a known bitrate ≤ the
ceiling; an unknown bitrate is not ready. A ready file is **copied, not encoded** (`-c copy`):
with the metadata switch on it is remuxed without its metadata — handing back the original
would keep a location the user asked to remove — and either way with the index first. No
picture is touched, so nothing is lost.

**The "output larger than input → hand back the original" rule does not apply** in this mode: a
small 1080×1920 original is exactly the file that blurs. The status-ready result is kept even
when it is larger.

## The screen (Compress video)

Where it lives today: the switch in `compress_video_view.dart`, its state
(`whatsAppOptimize`) in `compression_provider.dart`, the command in
`video_compression_service.dart` (`_buildCommand`), the presets and `VideoMetadata` in
`compression_presets.dart`. Several videos at once follow the same rule, decided per file.

- The existing **WhatsApp ready** switch is renamed **WhatsApp Status**, the label the editor's
  switch will use.
- On, it **overrides** the quality rows and the format control: both shown dimmed, the format
  fixed to MP4, with one line under the switch — "Overrides quality and format" — so the dimmed
  rows read as overridden rather than broken (the editor mockup's own pattern).
- The result screen's details read **WhatsApp Status** for the quality and **MP4** for the format.
  No tip about WhatsApp's HD option (the owner's call), though without it WhatsApp shrinks
  everything to about 480p whatever we hand it.

## Measurement — what sets the numbers

Done once now, and again whenever WhatsApp changes behaviour.

1. **Sources:** a real camera clip from the owner (20–30 s, handheld, movement, some low light)
   and the screen recording already in `Slimshot workspace/videos`.
2. **Variants**, made on this computer with FFmpeg's x264 (the encoder the app uses; needs a
   one-time FFmpeg install here): the rule above at ceilings of 1000, 1500, 2000, 2500, 3000 and
   4000 kbps; one 1080×1920 control; one 720×1612 (long side over 1280) to learn which side
   WhatsApp limits; one without the denoise.
3. **The owner** posts each to Status with HD on, views it on a second phone, and copies what
   WhatsApp delivered from that phone's `Android/media/com.whatsapp/WhatsApp/Media/.Statuses`.
4. **Compare** each delivered copy with what was posted: resolution, bitrate, encoding, and
   whether the bytes are identical (posted as-is).
5. **Decide:** the ceiling is the highest bitrate WhatsApp passes through untouched, less 10%.
   If nothing passes through, the ceiling is where WhatsApp's copy looks best side by side, and the
   shape rules still stand. Record the findings beside the constant.

The implementation does not wait for this: it ships with the provisional ceiling and the
measurement replaces one number.

## Testing

- **A pure plan**, `statusPlan(VideoProbe) → StatusPlan`: output size, frame rate, whether to
  tone-map, the filter chain, the x264 and audio arguments, and the passthrough decision. Unit
  tests pin every row of the table above, including portrait/landscape/square, no upscale, odd
  sizes, 60/50/25/24 fps and variable rate, PQ/HLG/10-bit SDR, the passthrough cases, multi-
  channel and missing audio. The command string is built from the plan, and a test pins it.
- **The probe** (`getVideoMetadata`) grows what the plan needs: frame rate (`r_frame_rate` and
  `avg_frame_rate`), pixel format / bit depth, colour transfer and primaries, rotation, and the
  audio stream's channels and sample rate.
- **Screen tests:** the switch overrides and dims the quality rows and format; no overflow at
  320 px with text at 1.3×, as the screen's tests already pin.
- **On the device** (only a device can say): the measurement above, an HDR clip's colours, the
  encode time of a one-minute clip on the Infinix, and the owner's own before/after on Status.

## Constraints

- FFmpegKit `ffmpeg_kit_flutter_new` (full-gpl: x264 and zimg present). x264 is GPL, which the
  app already ships today; this design adds no new licence exposure.
- Low-end Android is the target (`minSdk` 24); never decide the pipeline from one device —
  probe each input.
- The app's conventions: colours from `AppColors`, minimal copy, tests first, analyzer unchanged.

## Left to the builder

The exact denoise strengths and CRF value (within "mild" and "quality-targeted"), progress
reporting, and how the plan object is shaped — as long as it stays pure and the command is built
from it.
