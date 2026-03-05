import SwiftUI

struct HeartRateGuidanceCard: View {
    @ObservedObject var viewModel: TimerViewModel
    var showInstructions: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Heart Rate Guide", systemImage: "heart.text.square")
                .font(.headline)

            Picker("Max HR method", selection: $viewModel.useCustomMaxHR) {
                Text("Based on age").tag(false)
                Text("Custom Heart Rate").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.useCustomMaxHR) { _, isCustom in
                if isCustom && viewModel.customMaxHR == 0 {
                    viewModel.customMaxHR = viewModel.maximumHeartRate
                }
            }

            if viewModel.useCustomMaxHR {
                Stepper(value: $viewModel.customMaxHR, in: 100...220) {
                    Text("My max heart rate: \(viewModel.customMaxHR) BPM")
                        .font(.subheadline)
                }
            } else {
                Stepper(value: $viewModel.userAge,
                        in: TimerViewModel.minimumSupportedAge...TimerViewModel.maximumSupportedAge) {
                    Text("Age: \(viewModel.userAge)")
                        .font(.subheadline)
                }
                Text(viewModel.userAge >= 40
                     ? "Using Tanaka formula (208 − 0.7 × age)"
                     : "Using 220 − age")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Maximum heart rate: \(viewModel.maximumHeartRate) BPM")
                Text("High-intensity target (4 min): \(viewModel.highIntensityTargetRange.lowerBound)–\(viewModel.highIntensityTargetRange.upperBound) BPM")
                Text("Recovery target: \(viewModel.recoveryTargetRange.lowerBound)–\(viewModel.recoveryTargetRange.upperBound) BPM")
            }
            .font(.subheadline)

            if showInstructions {
                Text("Your max heart rate (MHR) is estimated from your age. For Norwegian 4x4, aim for 85–95% of MHR during each 4-minute high-intensity interval, and let your heart rate drop to 60–70% during recovery. If you know your actual MHR from a field test or VO₂ max assessment, switch to Custom Heart Rate for more accurate zones.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .onAppear {
            if viewModel.useCustomMaxHR && viewModel.customMaxHR == 0 {
                viewModel.customMaxHR = viewModel.maximumHeartRate
            }
        }
    }
}
