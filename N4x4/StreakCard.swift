import SwiftUI

struct StreakCard: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showingShareSheet = false
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let daySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with streak count
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: flameIcon)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(flameGradient)
                            
                        
                        Text("\(viewModel.currentStreak)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(streakColor)
                    }
                    
                    Text("Week Streak")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Longest streak badge
                if viewModel.longestStreak > 0 {
                    VStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("\(viewModel.longestStreak)")
                            .font(.headline.weight(.bold))
                        Text("Best")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.orange.opacity(0.15))
                    )
                }
            }
            
            // Weekly calendar visualization
            VStack(spacing: 8) {
                Text("This Month")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Day headers
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(daySymbols, id: \.self) { day in
                        Text(day)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Workout days grid
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<currentMonthDays, id: \.self) { index in
                        let dayNumber = index + 1
                        let hasWorkout = hasWorkoutOnDay(dayNumber)
                        let isToday = isToday(dayNumber)
                        let isFuture = isFutureDay(dayNumber)
                        
                        ZStack {
                            Circle()
                                .fill(backgroundColorFor(hasWorkout: hasWorkout, isToday: isToday, isFuture: isFuture))
                            
                            if hasWorkout {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            } else if !isFuture {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            }
                            
                            if isToday {
                                Circle()
                                    .stroke(ringColor, lineWidth: 2)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .foregroundStyle(isFuture ? Color.gray.opacity(0.5) : .primary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            
            // Motivational message
            if viewModel.currentStreak > 0 {
                Text(motivationalMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(motivationalColor)
                    .multilineTextAlignment(.center)
            }
            
            // Milestone badges
            HStack(spacing: 12) {
                MilestoneBadge(days: 7, currentStreak: viewModel.currentStreak, label: "7 Days", icon: "7.circle.fill")
                MilestoneBadge(days: 30, currentStreak: viewModel.currentStreak, label: "30 Days", icon: "30.circle.fill")
                MilestoneBadge(days: 100, currentStreak: viewModel.currentStreak, label: "100 Days", icon: "100.circle.fill")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    // MARK: - Computed Properties
    
    private var currentMonthDays: Int {
        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now)
        return range?.count ?? 30
    }
    
    private var flameIcon: String {
        if viewModel.currentStreak == 0 {
            return "flame"
        } else if viewModel.currentStreak < 7 {
            return "flame"
        } else if viewModel.currentStreak < 30 {
            return "flame.fill"
        } else {
            return "flame.circle.fill"
        }
    }
    
    private var flameGradient: LinearGradient {
        if viewModel.currentStreak == 0 {
            return LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
        } else if viewModel.currentStreak < 7 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
        } else if viewModel.currentStreak < 30 {
            return LinearGradient(colors: [.orange, .yellow, .red], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.red, .orange, .yellow, .white], startPoint: .top, endPoint: .bottom)
        }
    }
    
    private var streakColor: LinearGradient {
        if viewModel.currentStreak == 0 {
            return LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
        } else if viewModel.currentStreak < 7 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
        } else if viewModel.currentStreak < 30 {
            return LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.red, .orange, .yellow], startPoint: .top, endPoint: .bottom)
        }
    }
    
    private var motivationalMessage: String {
        let streak = viewModel.currentStreak
        let messages: [(Int, String)]
        
        if streak == 0 {
            messages = [
                (0, "Every journey begins with a single workout! 💪"),
                (0, "Your Viking awaits - time to start your streak! ⚔️"),
                (0, "The best time to start is now. Let's go! 🚀"),
            ]
        } else if streak == 1 {
            messages = [
                (1, "You've started something great! Keep it going! 🔥"),
                (1, "One down! The fire is lit! 🪓"),
            ]
        } else if streak < 7 {
            messages = [
                (3, "You're building momentum! Viking spirit! ⚔️"),
                (5, "A week of victories awaits you! 🏆"),
                (6, "Almost there! One more to reach a full week! 💪"),
            ]
        } else if streak < 30 {
            messages = [
                (10, "You're unstoppable! A true Viking! 🪓🔥"),
                (14, "Two weeks strong! Your dedication is impressive! 💪"),
                (21, "Three weeks! You're building an unstoppable habit! ⚔️"),
                (28, "One more week to legend status! 🎯"),
            ]
        } else if streak < 100 {
            messages = [
                (30, "LEGENDARY! A full month of dominance! 👑🔥"),
                (50, "Halfway to 100! You're unstoppable! ⚡"),
                (75, "75 weeks! Absolute domination! 🏆"),
                (90, "Just 10 more to triple digits! 🚀"),
            ]
        } else {
            messages = [
                (100, "100+ STREAKS! YOU ARE A LEGEND! 👑⚔️🔥"),
                (101, "The myths will sing of your dedication! 📜"),
            ]
        }
        
        // Find the highest matching message
        for message in messages.reversed() {
            if streak >= message.0 {
                return message.1
            }
        }
        return messages.last?.1 ?? "You're a Viking legend! ⚔️"
    }
    
    private var motivationalColor: Color {
        let streak = viewModel.currentStreak
        if streak == 0 {
            return .secondary
        } else if streak < 7 {
            return .orange
        } else if streak < 30 {
            return .red
        } else {
            return .purple
        }
    }
    
    private var ringColor: Color {
        let streak = viewModel.currentStreak
        if streak == 0 {
            return .gray
        } else if streak < 7 {
            return .orange
        } else if streak < 30 {
            return .red
        } else {
            return .purple
        }
    }
    
    // MARK: - Helper Functions
    
    private func hasWorkoutOnDay(_ day: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return false }
        
        for entry in viewModel.workoutLogEntries {
            if monthInterval.contains(entry.completedAt) {
                let entryDay = calendar.component(.day, from: entry.completedAt)
                if entryDay == day {
                    return true
                }
            }
        }
        return false
    }
    
    private func isToday(_ day: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.day, from: now) == day
    }
    
    private func isFutureDay(_ day: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.component(.day, from: now)
        return day > today
    }
    
    private func backgroundColorFor(hasWorkout: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isFuture {
            return .clear
        } else if hasWorkout {
            return .green
        } else if isToday {
            return Color(UIColor.systemGray5)
        } else {
            return .clear
        }
    }
}

struct MilestoneBadge: View {
    let days: Int
    let currentStreak: Int
    let label: String
    let icon: String
    
    var isAchieved: Bool {
        currentStreak >= days
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isAchieved ? icon : "circle")
                .font(.title2)
                .foregroundStyle(isAchieved ? achievedColor : Color.gray.opacity(0.5))
            
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isAchieved ? .primary : Color.gray.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isAchieved ? achievedColor.opacity(0.15) : Color.clear)
        )
    }
    
    private var achievedColor: Color {
        if days == 7 {
            return .orange
        } else if days == 30 {
            return .red
        } else {
            return .purple
        }
    }
}
