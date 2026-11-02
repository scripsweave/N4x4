# Reply draft — intermittent Apple Watch heart rate

Not sent. The "next update" is 5.15 (submitted 2026-11-02; check it is live
before promising it). Personalise the greeting before sending.

Hi,

Thank you for such a thorough report — the diagnostics and the steps you'd
already tried made this much easier to narrow down. Your workout history is
safe: nothing below touches it, and please don't delete the iPhone app.

**What your diagnostics tell us**

Your iPhone received 35 Watch heart-rate readings and rejected none, and
readings arrived about one second after they were measured. So when the Watch
sends heart rate, the connection works. During the workouts that failed, the
Watch didn't send anything. That points to the Watch's heart-rate session
rather than the Bluetooth/Wi-Fi link between the devices.

The most likely cause is Health's **Heart Rate read** permission, which you
found switched off. N4x4's Watch app needs it to see its own sensor readings.
Until now only the Watch asked for it, with a small on-wrist prompt, so it was
easy to miss. (The repeated permission requests came from recent updates adding
heart-rate and calorie saving, plus reinstalling the Watch app. They should
settle down.)

**Please try this**

1. On your iPhone: Settings → Privacy & Security → Health → N4x4. Make sure
   Heart Rate, Active Energy and Workouts are on under both read and write.
2. On your Watch, make sure Low Power Mode is off (swipe up or press the side
   button to open Control Center).
3. Close N4x4 on the Watch and reopen it: double-click the Digital Crown,
   swipe the N4x4 card left and tap ✕. This clears any half-started
   heart-rate session.
4. Make sure no other workout (for example Apple's Workout app) is running.
   Only one workout app can use the Watch sensor this way at a time, and
   starting another one stops N4x4's.
5. Open N4x4 on your iPhone, keep it nearby, then start the workout from your
   Watch. Allow about 20 seconds for the first reading.

**If it fails again, these details would pin it down**

- On the Watch, does the heart show a number or "--"?
- Turn the Digital Crown to the second page. Is there an orange message or a
  Retry Heart Rate button? Please note the exact wording, then tap Retry.
- Is there a small Watch icon next to "ROUND …" at the top? That means the
  Watch started the workout without the iPhone.
- While it's still failing, on the iPhone go to Settings → Health & Devices →
  Copy Diagnostics and send the **whole** text, including the first lines
  (they show the app and iOS version).
- Your Watch model and watchOS version.

**In the next update (5.15)**

- The iPhone will ask for Heart Rate access too.
- If the sensor stays silent, the Watch will say "NO HR" and explain what to
  check, with Retry Heart Rate restarting the sensor without ending your
  workout.
- Copy Diagnostics will include the Watch's own view of its heart-rate session.
  One copy taken during a failure should tell us exactly where it stops.

Thanks again for your patience and for helping make N4x4 better.

Jan
