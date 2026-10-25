# Animated N4x4 product-page header

User selected the chrome-ring concept and authorized animation and publication
on 24 October 2026.

- [Play the final 8-second loop](N4x4-Chrome-Ring-Header-v2.mp4)
- [Looping browser preview](preview.html)
- [Poster](poster.png)
- [Upload/publication record](publication.json)
- [QA measurements](qa-report.json)

## Produced and verified

The selected imagegen artwork is preserved. Core Image animates the existing
four orange work arcs clockwise, green recovery ports between efforts, a faint
travelling metal highlight and floor reflections. No device/UI artwork is used.
The original selected image and exact imagegen prompt are in
`../../../docs/design/app-store-creatives-2026-10-24/`.

Output: H.264 MP4, **3840×1646**, **30 fps**, **8 seconds**, **240 decoded
frames**, no audio. Source frames at 0 and 8 seconds are pixel-identical.
The encoded seam's mean absolute RGB difference is 0.990/255; ordinary adjacent
frames are 0.638/255, including compression differences. Decoded work/recovery
frames were visually checked. Publisher regression checks: **4 passed / 14
assertions**. Native AVAssetReader compressed buffers include codec metadata;
the 240-frame count is verified from decoded BGRA buffers.

Reproduce with Xcode selected explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift \
  AppStore/creative-assets/chrome-ring/render.swift \
  docs/design/app-store-creatives-2026-10-24/A-chrome-ring-header.png \
  /tmp/N4x4-header-new-export.mp4
```

## Apple review and publication queue

The video is **APPROVED and published** as the active English product-page
header on the live 5.7 version. The automatic publisher first verified
publication at **2026-10-24 20:48:08 UTC**; the live placement was independently
reverified on 25 October. Placement `36000018-e8a7-8c74-8f18-1362a43b6fb1`
is **ACTIVE**, linked to approved video
`0a000018-e8a7-8c74-8128-2b84ccf4117b`.

The standalone artwork review was submitted at 2026-10-24 20:15:06 UTC,
review `f57fe4ad-e288-4d65-976e-7a4084eaedba`. Apple approval arrived before
the publisher's 20:48 check. The separate **5.10 app submission is still
WAITING_FOR_REVIEW**. The publisher continues until the header is present on
5.10 (or newer) after app release, then disables itself.

User LaunchAgent **`com.n4x4.chrome-ring-publication`** is installed and was
verified to run successfully. It checks every **900 seconds** while this Mac
is awake and the user is logged in. It also runs at login, so a sleeping/offline
Mac resumes the queue later. Files:

- `~/Library/LaunchAgents/com.n4x4.chrome-ring-publication.plist`
- `~/.local/share/n4x4-header-publication/publish-approved.rb` (frozen copy)
- `~/.local/share/n4x4-header-publication/state.json` (authoritative live status)
- `~/.local/share/n4x4-header-publication/publisher.log` and `publisher-error.log`

The worker reads the existing private App Store API credential; no credential
was copied into the repo or a cloud service. It publishes only this exact
approved video as the English product-page header of the newest live iOS
version of N4x4. It preserves a different manually selected header. If 5.7 is
still live, it publishes there first and continues until 5.10 (or newer) is
live and has this header. It verifies placement, then disables/unloads itself.
App-version metadata, screenshots and search creatives are not changed.
An Apple rejection or API error is recorded for inspection rather than treated
as successful publication.

Inspect or stop the queue:

```sh
cat ~/.local/share/n4x4-header-publication/state.json
launchctl print gui/$(id -u)/com.n4x4.chrome-ring-publication
launchctl bootout gui/$(id -u)/com.n4x4.chrome-ring-publication
```

Files/code are on `design/animated-store-header`; do not push this to main
without a new version because main still triggers Xcode Cloud delivery.

Apple references: [creative specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications),
[video upload API](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-video-assets),
[standalone approval and live-page updates](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets).
