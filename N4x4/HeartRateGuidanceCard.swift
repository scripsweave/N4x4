import SwiftUI

struct HeartRateGuidanceCard: View {
    @ObservedObject var viewModel: TimerViewModel
    var showInstructions: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Heart Rate Guide", systemImage: "heart.text.square")
                .font(.headline)

            Stepper(value: $viewModel.userAge, in: TimerViewModel.minimumSupportedAge...TimerViewModel.maximumSupportedAge) {
                Text("Age: \(viewModel.userAge)")
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Maximum heart rate: \(viewModel.maximumHeartRate) BPM")
                Text("High-intensity target (4 min): \(viewModel.highIntensityTargetRange.lowerBound)-\(viewModel.highIntensityTargetRange.upperBound) BPM")
                Text("Recovery target: \(viewModel.recoveryTargetRange.lowerBound)-\(viewModel.recoveryTargetRange.upperBound) BPM")
            }
            .font(.subheadline)

            if showInstructions {
                Text("To determine your maximum heart rate (MHR), subtract your age from 220. Example: if you’re 40 years old, 220 - 40 = 180, so your MHR is 180 BPM. For Norwegian 4x4, aim for 85-95% of your MHR during each 4-minute high-intensity interval (153-171 BPM in this example). During recovery periods, let your heart rate drop to around 60-70% of MHR (108-126 BPM in this example).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }
}
