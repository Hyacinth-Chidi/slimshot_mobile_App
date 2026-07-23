# Slimshot AI — Version 3 Roadmap

> **Current Version:** 2.0.0  
> **Target:** Version 3.0.0  
> **Status:** Planning

---

## 🎯 Flagship Feature: Fixed Canvas Architecture

### Concept
Transform the video editor from a "video-is-the-canvas" model to a **"fixed workspace canvas"** model — exactly how CapCut, InShot, and Premiere Rush work.

### How It Works
- The editor starts with a **master canvas** (default: 9:16 for Reels/TikTok).
- Any video imported becomes a **layer inside the canvas**, auto-fitted to fill the width.
- If the video aspect ratio doesn't match the canvas, the empty space is filled with black (or a user-chosen background color via the Background tool).
- Users can **pinch-to-zoom and drag** the video freely at any time without needing to switch to a "Zoom" tool.
- When a video segment is selected on the timeline, its **bounding edges are highlighted** on the preview, signaling it's ready to be repositioned.

### Why This Matters
- **Social-First Editing:** Users edit for TikTok (9:16), YouTube (16:9), Instagram (1:1, 4:5). The canvas adapts to the platform, not the source video.
- **Creative Freedom:** Empty space = creative opportunity. Users can use the Background tool to fill it with color, blur, or gradient.
- **Intuitive UX:** Pinch-to-zoom without a tool switch is what users expect from modern editors.

### Performance Impact
- **Preview:** No performance impact. It's just a layout change in Flutter widgets.
- **Export:** Negligible (~0.5-1s added). FFmpeg simply composites the video onto a fixed-size canvas using one extra `-filter_complex` line.
- **Existing features:** Filters, text overlays, stickers, transitions — all unaffected.

### Risk Assessment

| Area | Risk | Notes |
|---|---|---|
| Basic playback | ✅ None | Video player doesn't change |
| Text/Image/Video overlays | ⚠️ Medium | Overlay positions are relative to the canvas — need to verify they still land correctly |
| Filters | ✅ None | Filters apply to the video layer, not the canvas |
| Crop tool | ⚠️ Medium | Decide: does crop apply to video layer or canvas? |
| Zoom tool | ✅ None | Gets replaced by native free-transform gesture (simplifies things) |
| FFmpeg export | ⚠️ Medium | Export command builder needs canvas-aware positioning |
| Draft saving/loading | ⚠️ Low | Save canvas ratio and video position in draft model |

### Files to Modify

1. **`video_editor_state.dart`** — Add `canvasAspectRatio` field (default 9:16). Existing `videoScale` and `videoPan` become the primary positioning mechanism.
2. **`video_preview_canvas.dart`** — Biggest change. Outer `AspectRatio` uses canvas ratio instead of video ratio. Video becomes a positioned child layer. Add pinch-to-zoom gesture directly on the video.
3. **`crop_panel.dart`** — Ratio buttons (16:9, 9:16, 1:1, 4:5) change the canvas ratio instead of cropping the video. "Custom" crop still works for freeform video cropping.
4. **`video_editor_notifier.dart`** — Add `setCanvasAspectRatio()` method. Auto-fit video when canvas ratio changes.
5. **`ffmpeg_export_service.dart`** — Update export command: create canvas → scale video → position video → overlay text/images → encode.
6. **`video_editor_toolbar.dart`** — Possibly remove standalone "Zoom" tool (zoom becomes a native gesture).

---

## 💰 In-App Purchases & Subscriptions

### Concept
Currently, users unlock "Pro" features by watching a Rewarded Ad. In V3, integrate **RevenueCat** or standard **Google Play Billing** to offer:
- A monthly subscription (e.g., $2.99/month) to unlock all Pro features permanently.
- A one-time purchase option to remove interstitial ads.
- Rewarded ads remain as a free alternative for users who can't/won't pay.

---

## 🔥 Firebase Crashlytics & Analytics

### Concept
Native video rendering (FFmpeg) behaves differently across thousands of Android devices. Add **Firebase Crashlytics** so we can:
- See exactly if/why a user's phone failed to export a 4K video.
- Track which features are most used.
- Monitor crash-free rates across device models.

---

## 🎓 Interactive Onboarding Tutorial

### Concept
The video editor is now powerful with many tools. Add a **guided tooltip overlay** the first time users open the editor:
- Teach them how to split, trim, add text, and use filters.
- Show them the timeline, the tool drawer, and the export flow.
- Allow users to skip or replay the tutorial from Settings.

---

## ☁️ Cloud Drafts (Future)

### Concept
Sync workspace drafts to the cloud so users can:
- Continue editing on another device.
- Reinstall without losing their projects.
- Share draft projects with collaborators.

---

## 📝 Notes
- **Priority order:** Fixed Canvas → Crashlytics → IAP → Onboarding → Cloud Drafts
- **Ship V2 first**, collect user feedback, then build V3 based on real usage data.
