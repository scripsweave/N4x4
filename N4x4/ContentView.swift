import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = TimerViewModel()

    var body: some View {
        TimerView(viewModel: viewModel)
    }
}
//import SwiftUI
//
//struct ContentView: View {
//    @StateObject var viewModel = TimerViewModel()
//    @State private var showSettings = false
//
//    var body: some View {
//        NavigationView {
//            TimerView(viewModel: viewModel)
//                .navigationBarTitleDisplayMode(.inline)
//                .toolbar {
//                    ToolbarItem(placement: .navigationBarTrailing) {
//                        Button(action: {
//                            showSettings.toggle()
//                        }) {
//                            Image(systemName: "gearshape.fill")
//                                .font(.title2)
//                                .foregroundColor(.gray) // Set the gear icon color to grey
//                        }
//                    }
//                }
//                .sheet(isPresented: $showSettings) {
//                    SettingsView(viewModel: viewModel)
//                }
//        }
//        .navigationViewStyle(StackNavigationViewStyle())
//    }
//}
