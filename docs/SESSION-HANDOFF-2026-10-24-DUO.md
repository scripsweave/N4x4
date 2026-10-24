# iPhone Duo implementation — in progress

User authorized implementation, authentic Duo screenshots and App Store publication on 24 October. Working branch: `feature/iphone-duo`. Proposed shipping version: 5.10 (all six configs).

Implemented first pass: native split arrangements for Home and Workout on regular-width displays; reserved-region detection for propped workouts; large HR panel and next-interval preview; native History list/detail navigation with retained entry selection and existing sharing/deletion/Health views. Older OS and accessibility layouts retain scrolling fallbacks. Timer and Health behavior are unchanged. No optional live HR chart.

Initial Xcode 26.6 validation: simulator build succeeded; 243 unit tests and the two targeted rotation/History UI regressions passed, `/tmp/N4x4-duo-initial-tests.xcresult`. Native Duo code still needs compilation and visual validation.

Xcode 27.1 installed via App Store; original retained at `/Applications/Xcode-26.6.app`. Updated Apple license acceptance is pending user action. Native runtime setup follows.

Cloud development workflow created (no archive/delivery): `08771d11-b415-43ae-b941-2175a460f659`, pinned Xcode 27.1 (27A9275), with phone and Watch builds plus Duo tests. Existing Default main-delivery workflow is unchanged.

App Store API check found 5.9 REJECTED, 5.7 live. Rejection message needs browser login; user asked asynchronously to sign into Safari. Do not submit until the rejection reason is understood and addressed.

Design boards and research: [Duo brief](design/iphone-duo-2026-10-24/README.md).
