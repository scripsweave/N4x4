# Settings Redesign Plan — iOS Settings Style

2026-07-22 · Companion mockups: https://claude.ai/code/artifact/bbe60b82-cb34-476a-8609-2f2a0820ae61
Follows commit `464ad20` (default workout setting, Kettlebells modality, haptics rework).

**Status: IMPLEMENTED in v4.6** (same day). Jan's calls on the open questions:
Training Tips → Home screen; reminder names confirmed; search shipped in v1.
Detail pages live in `N4x4/SettingsSubpages.swift`, top level in `SettingsView.swift`.

## Problem

`SettingsView.swift` is one flat `Form` with 20 sections (~35 controls). The two
most-used settings (default workout type; training days & reminders) sit at
positions 1 and 15 of one long scroll. Kindred controls are scattered: reminders
live in two sections, heart-rate coaching in three.

## Proposal

Restructure like the iOS Settings app: a short top level of grouped rows
(icon tile · label · current value · chevron) with the controls on subpages.
Regrouping only — no storage keys change, no migration, watch sync untouched.

### Top-level IA (16 rows, max depth 2)

- **Pinned (no header)** — Default Workout (inline picker) · Training Days & Reminders
- **Workout** — Intervals & Durations (count, warm-up/work/recovery/cool-down, skip confirmations)
- **Coaching** — Audio (mode + prompt toggles) · Haptics · Heart-Rate Zones & Alerts (age/max HR, guide, alert channels)
- **Devices & Health** — Apple Watch · Heart Rate Monitor · Apple Health
- **Progress** — VO₂ Max Goal · Units (inline picker)
- **General** — Display · Training Tips · Replay Onboarding · Send Feedback · **Reset All Settings** (red, last)

### Key decisions

- **Value previews on every top-level row** ("Kettlebells", "Tue · Thu", "4 × 4:00",
  "Voice") — most Settings visits are checks, not changes.
- **Pinned group is unlabeled** so rows can be re-pinned without renaming anything.
- **Single-picker settings stay inline** (Default Workout, Units); anything with
  two or more controls gets a subpage.
- **Permission-denied banners** render inside the page that needs the permission.

## Implementation phases

1. **Scaffold** — split `SettingsView.swift` into `Settings/` (one file per
   subpage: `TrainingDaysSettingsView`, `IntervalSettingsView`, `AudioSettingsView`,
   `HapticsSettingsView`, `ZoneSettingsView`, device views). Plain `Form`s pushed
   via `NavigationLink`; all bindings stay on `TimerViewModel`.
2. **Top level** — reusable `SettingsRow(icon:tint:title:value:)`; value strings
   from small computed properties on the view model (e.g. `reminderSummary`).
   Swap `NavigationView` → `NavigationStack` while touching this.
3. **Merge kindred sections** — reminders + interval notifications + day grid →
   Training Days; intervals + durations + skip confirmations → Intervals;
   zone alerts + HR guide + age/max HR → Zones.
4. **Polish + guardrails** — unit-test the row summary strings; verify both the
   embedded (tab) and sheet presentations via the `embedded` flag; ship behind a
   one-line rollback flag like the home redesign (`useRedesignedUI` pattern).

## Open questions (for Jan)

- Keep Training Tips in Settings, or move it to the home/Learn surface?
- Reminder naming: night-before / morning-of / comeback nudges — right labels?
- iOS-style search field at the top: v1 or defer?
