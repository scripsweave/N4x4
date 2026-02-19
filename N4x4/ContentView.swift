import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = TimerViewModel()

    var body: some View {
        TimerView(viewModel: viewModel)
    }
}
