#!/usr/bin/env python3
"""Seed illustrative data in a dedicated simulator, never a physical device.

Install the Debug app in a simulator named 'N4x4 Duo Review', then run:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    python3 AppStore/seed-duo-captures.py SIMULATOR_UDID
All data is synthetic. Captures must come from the actual running app.
"""
import argparse
import datetime as dt
import json
import math
from pathlib import Path
import plistlib
import subprocess
import uuid

BUNDLE = 'Jan-van-Rensburg.N4x4'


def simctl(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check,
                          capture_output=True, text=True)


def iso(date):
    return date.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def session(date, number):
    phases = [('warmup', 600)]
    for interval in range(4):
        phases.append(('work', 240))
        if interval < 3:
            phases.append(('recovery', 180))
    phases.append(('cooldown', 300))
    spans, samples = [], []
    cursor, work, bpm = 0, 0, 100.0
    for kind, duration in phases:
        work += kind == 'work'
        lo, hi = (153, 171) if kind == 'work' else (108, 126) if kind == 'recovery' else (0, 0)
        spans.append(dict(kind=kind, workNumber=work if kind == 'work' else 0,
                          start=cursor, end=cursor + duration, targetLo=lo, targetHi=hi))
        for elapsed in range(0, duration, 2):
            target = 165 + 2 * math.sin(elapsed / 32) if kind == 'work' else 118 if kind == 'recovery' else 128 if kind == 'warmup' else 105
            bpm += (target - bpm) * 0.055
            samples.append(dict(t=cursor + elapsed, bpm=round(bpm + math.sin(elapsed / 13), 1)))
        cursor += duration
    eligible = [(sample, span) for span in spans if span['kind'] == 'work'
                for sample in samples if span['start'] <= sample['t'] < span['end']]
    in_zone = round(100 * sum(span['targetLo'] <= sample['bpm'] <= span['targetHi']
                             for sample, span in eligible) / len(eligible))
    summary = dict(avgBPM=round(sum(s['bpm'] for s in samples) / len(samples)),
                   maxBPM=round(max(s['bpm'] for s in samples)), workInZonePct=in_zone,
                   sparkline=[round(samples[round(i * (len(samples) - 1) / 39)]['bpm']) for i in range(40)])
    entry_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f'n4x4-duo-capture-{number}')).upper()
    entry = dict(id=entry_id, completedAt=iso(date), workoutType='Run', notes='', modality='Outdoor Run',
                 sessionBreakdown=dict(totalDuration=cursor, warmupDuration=600, highIntensityDuration=960,
                                       recoveryDuration=540, cooldownDuration=300, cooldownSkipped=False),
                 intervalPerformances=[dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL, f'n4x4-duo-{number}-interval-{i}')),
                                            intervalNumber=i, primary=10 + i * .2, note='') for i in range(1, 5)],
                 hrSummary=summary)
    series = dict(samples=samples, spans=spans, startedAt=iso(date - dt.timedelta(seconds=cursor)))
    return entry, series


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    args = parser.parse_args()
    inventory = json.loads(simctl('list', 'devices', '--json').stdout)
    device = next((d for devices in inventory['devices'].values() for d in devices
                   if d['udid'] == args.device), None)
    if (not device or device['name'] != 'N4x4 Duo Review' or device['state'] != 'Booted'
            or device.get('deviceTypeIdentifier') != 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'):
        parser.error("Use a booted, dedicated simulator named 'N4x4 Duo Review'.")
    container = Path(simctl('get_app_container', args.device, BUNDLE, 'data').stdout.strip())
    simctl('terminate', args.device, BUNDLE, check=False)
    now = dt.datetime.now().astimezone().replace(hour=9, minute=0, second=0, microsecond=0)
    entries = []
    series_dir = container / 'Library' / 'Application Support' / 'HeartRateSeries'
    series_dir.mkdir(parents=True, exist_ok=True)
    for number in range(27):
        # Three sessions per week over nine weeks, newest first.
        day_offset = number // 3 * 7 + (number % 3) * 2
        entry, series = session(now - dt.timedelta(days=day_offset), number)
        entries.append(entry)
        (series_dir / f"{entry['id']}.json").write_text(json.dumps(series))
    preferences = dict(hasCompletedOnboarding=True, hasSeenHRSourcesAnnouncement=True,
                       hasSeenWatchUpgradePrompt=True, healthKitEnabled=False,
                       healthKitUserOptedOut=True, appleSensorHREnabled=False,
                       workoutRemindersEnabled=False, notificationsEnabled=False,
                       audioModeRaw='Silent', hapticsEnabled=False, liveActivitiesEnabled=False,
                       warmupDuration=600, highIntensityDuration=240, restDuration=180,
                       cooldownDuration=300, cooldownEnabled=True, numberOfIntervals=4,
                       userAge=40, hasRequestedAppReview=True, longestStreak=9,
                       defaultWorkoutTypeRaw='Run', preferredModalityRaw='Outdoor Run',
                       shownMilestonesData='[1,5,10,25,50,100]',
                       workoutLogEntriesData=json.dumps(entries))
    pref_path = container / 'Library' / 'Preferences' / f'{BUNDLE}.plist'
    pref_path.parent.mkdir(parents=True, exist_ok=True)
    existing = plistlib.loads(pref_path.read_bytes()) if pref_path.exists() else {}
    existing.update(preferences)
    pref_path.write_bytes(plistlib.dumps(existing, fmt=plistlib.FMT_BINARY))
    # A UI-test session can leave cached preferences and an inactive inner
    # scene. Restart only this dedicated device before reading the fixture.
    simctl('shutdown', args.device)
    simctl('boot', args.device)
    simctl('bootstatus', args.device, '-b')
    print(f'Seeded {len(entries)} synthetic sessions in {device["name"]}.')
    print('Launch the Debug app with SIMCTL_CHILD_N4X4_DEMO_HEART_RATE=166 for workout captures.')


if __name__ == '__main__':
    main()
