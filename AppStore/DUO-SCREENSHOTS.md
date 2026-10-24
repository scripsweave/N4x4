# iPhone Duo screenshots (5.10)

These screenshots are captured from the running N4x4 app in Xcode 27.1's iOS
27.1 iPhone Duo simulator. Generated concept art lives separately under
`docs/design/iphone-duo-2026-10-24/`; it is not App Store media.

`seed-duo-captures.py` writes illustrative workout history only to a booted,
dedicated simulator named **N4x4 Duo Review**. Live HR uses the existing DEBUG
fixture through the normal source aggregator. No personal Health records or
credentials are included. The release build does not enable demo readings.

Raw simulator captures are in `raw-duo/`. Upload copies in `screenshots/duo/`
retain the exact pixels and dimensions, with the PNG alpha channel removed.
No invented screen UI, device frame or resized screenshot is used.

Apple's asset-library reference catalog maps both displays to
`IPHONE_DUO_PROFILE`: outer 1398×2034 / 2034×1398; inner 2007×2853 /
2853×2007. The profile allows at most ten screenshots in total. The upload
manifest records SHA-256, processed image specification, image and placement
IDs. Existing screenshots for other device profiles are preserved.

References:
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets
- https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces

## Review evidence required separately

Apple rejected 5.9 under Guideline 2.5.4 and explicitly requested recordings
made on a **physical iOS device**. Simulator screenshots cannot satisfy that:

1. Wear/connect a standard BLE heart-rate monitor through Settings → Health &
   Devices → Heart Rate Monitor. Record the connection, live BPM during a
   workout, background the app, then return to the continuing workout.
2. Select Voice Prompts in Settings → Audio. Use short intervals and an
   audible media volume. Record starting the workout, returning to the iPhone
   Home Screen and hearing a subsequent spoken workout cue in the background.

Attach the recordings to App Review Information and reference their exact
filenames in the review notes. No recording or physical-device validation is
claimed until those files actually exist.

Physical review evidence was supplied on 24 October. Apple accepts one review attachment, so both original recordings are joined in `N4x4-physical-device-review.mp4` (100.15 seconds): Bluetooth at 00:00–01:00, Home Screen audio at 01:00–01:40, with the background halfway cue near 01:31. The private attachment is COMPLETE. Review notes identify these timestamps; recordings are excluded from git.
