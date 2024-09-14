
// TimerViewModel
import SwiftUI
import Combine
import AVFoundation
import UserNotifications

class TimerViewModel: ObservableObject {
    // User settings stored in UserDefaults
    @AppStorage("numberOfIntervals") var numberOfIntervals: Int = 4 {
        didSet {
            if numberOfIntervals < 1 {
                numberOfIntervals = 1
            }
            reset()
        }
    }
    @AppStorage("warmupDuration") var warmupDuration: TimeInterval = 5 * 60 {
        didSet { reset() }
    }
    @AppStorage("highIntensityDuration") var highIntensityDuration: TimeInterval = 4 * 60 {
        didSet { reset() }
    }
    @AppStorage("restDuration") var restDuration: TimeInterval = 3 * 60 {
        didSet { reset() }
    }
    @AppStorage("alarmEnabled") var alarmEnabled: Bool = true
    @AppStorage("preventSleep") var preventSleep: Bool = true
    
    //Notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false {
            didSet {
                if notificationsEnabled && !notificationPermissionRequested {
                    requestNotificationPermission()
                }
            }
        }
        
    @AppStorage("notificationPermissionRequested") var notificationPermissionRequested: Bool = false


    // Timer properties
    @Published var currentIntervalIndex: Int = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var isRunning: Bool = false

    // Interval counts
    @Published var highIntensityCount: Int = 0
    @Published var restCount: Int = 0

    // Completion message display control
    @Published var showCompletionMessage: Bool = false

    var intervals: [Interval] = []
    var timer: AnyCancellable?
    var player: AVAudioPlayer?

    init() {
        if numberOfIntervals < 1 {
            numberOfIntervals = 4 // Default value
        }
        setupIntervals()
    }

    func setupIntervals() {
        intervals.removeAll()
        highIntensityCount = 0
        restCount = 0

        // Conditionally add warm-up interval
        if warmupDuration > 0 {
            let warmup = Interval(name: "Warm Up", duration: warmupDuration, type: .warmup)
            intervals.append(warmup)
        }

        // High-intensity and rest intervals
        for i in 1...numberOfIntervals {
            // High-intensity interval
            let highIntensity = Interval(name: "High Intensity", duration: highIntensityDuration, type: .highIntensity)
            intervals.append(highIntensity)

            // Add rest interval only if it's not the last high-intensity interval
            if i < numberOfIntervals {
                let rest = Interval(name: "Rest", duration: restDuration, type: .rest)
                intervals.append(rest)
            }
        }

        currentIntervalIndex = 0
        timeRemaining = intervals.first?.duration ?? 0

        // Update counts based on the first interval
        updateCounts()
    }

    func updateCounts() {
        let currentType = intervals[currentIntervalIndex].type
        switch currentType {
        case .highIntensity:
            highIntensityCount += 1
        case .rest:
            restCount += 1
        default:
            break
        }
    }

    func startTimer() {
        isRunning = true
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.tick()
            }
    }

    func stopTimer() {
        isRunning = false
        timer?.cancel()
    }

    func tick() {
        guard isRunning else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            playAlarmIfNeeded()
            moveToNextInterval()
        }
    }

//    func moveToNextInterval() {
//        if currentIntervalIndex + 1 < intervals.count {
//            currentIntervalIndex += 1
//            timeRemaining = intervals[currentIntervalIndex].duration
//
//            // Update counts
//            updateCounts()
//        } else {
//            // Workout complete after the last interval
//            stopTimer()
//            showCompletionMessage = true
//        }
//    }
    
    func moveToNextInterval() {
            if currentIntervalIndex + 1 < intervals.count {
                currentIntervalIndex += 1
                timeRemaining = intervals[currentIntervalIndex].duration

                // Schedule notification for the next interval
                scheduleNotification(for: intervals[currentIntervalIndex])

                // Update counts
                updateCounts()
            } else {
                // Workout complete after the last interval
                stopTimer()
                showCompletionMessage = true
            }
        }

    func pause() {
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func skip() {
        playAlarmIfNeeded()
        moveToNextInterval()
    }

    func reset() {
        stopTimer()
        setupIntervals()
        isRunning = false
        showCompletionMessage = false
        // Counts are reset in setupIntervals()
    }

    func resetSettingsToDefaults() {
        numberOfIntervals = 4
        warmupDuration = 5 * 60
        highIntensityDuration = 4 * 60
        restDuration = 3 * 60
        alarmEnabled = true
        preventSleep = true
    }

    func playAlarmIfNeeded() {
        if alarmEnabled {
            playAlarm()
        }
    }

    func playAlarm() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing alarm sound: \(error.localizedDescription)")
        }
    }
    
    // Request notification permission
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.notificationPermissionRequested = true
                    if !granted {
                        self.notificationsEnabled = false
                    }
                }
                print("Notification permission granted: \(granted)")
            }
        }
    }

        // Schedule a notification
    func scheduleNotification(for interval: Interval) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "N4x4 Interval"
        content.body = "\(interval.name) interval is starting."
        content.sound = .default

        // Schedule notification to trigger when the interval starts
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
}

