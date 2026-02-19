import SwiftUI

struct HelpView: View {
    var body: some View {
        ZStack {
            // Background Image
            Image("background2")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            // Main Content
            ScrollView {
                VStack(spacing: 20) {
                    // App Logo
                    Image("n4x4")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .cornerRadius(20)
                        .padding(.top, 20)
                    
                    // App Title
                    Text("N4x4 App\nNorwegian 4x4 Protocol to increase your VO2 Max for endurance, health and longevity")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Download Button
                    Button(action: {
                        // Open App Store link
                        if let url = URL(string: "https://apps.apple.com/app/n4x4/id6686407796") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Image("download-on-the-app-store")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250)
                    }
                    
                    Text("Completely free. No sign-ups. No ads. No in-app purchases.")
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Boost Your Fitness with N4x4 – The Proven Way to Improve VO2 Max")
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Quote Section
                    VStack {
                        Text("\"VO2 Max is the single greatest predictor of lifespan.\" — Dr. Peter Attia")
                            .font(.system(size: 24))
                            .italic()
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Description Paragraphs
                    Group {
                        Text("The Norwegian 4x4 is the best High Intensity Interval Training (HIIT) protocol to increase your VO2 Max. It has nothing to do with cars. :-)")
                        
                        Text("The N4x4 app guides you through the gold-standard Norwegian 4x4 interval training. No fluff — just a simple, powerful tool to help you increase your VO2 Max, the key metric for longevity.")
                        
                        Text("The benefits of the Norwegian 4x4 protocol have been promoted by experts like Dr. Rhonda Patrick (no association with N4x4), who explains the protocol in this 90-second clip:")
                    }
                    .font(.system(size: 16))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    
                    // Info Sections
                    InfoSection(imageName: "heartmonitor", title: "How it works") {
                        Text("The Norwegian 4x4 is a high intensity interval training (HIIT) protocol with the following steps:")
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• 5-minute warm-up")
                            Text("• 4x rounds of:")
                            VStack(alignment: .leading, spacing: 5) {
                                Text("○ 4 minutes of intense cardio at 85-95% of your Maximum Heart Rate (MHR)")
                                Text("○ 3 minutes of light recovery")
                            }
                            .padding(.leading, 20)
                        }
                    }
                    
                    InfoSection(imageName: "running", title: "Recommended Exercises for N4x4") {
                        Text("You can do any exercise that gets your heart rate up to the required level. It's easier to use stationary equipment to keep the effort level constant. But perfect can be the enemy of good, and good is better than nothing. If you don't have stationary gym equipment, just find a place where you can run with as little variability as possible. A flat or steady incline run will work just fine. Here are some other exercise ideas:")
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• Running (treadmill makes it easier to control the intensity)")
                            Text("• Cycling (stationary is easier for intensity control)")
                            Text("• Swimming")
                            Text("• Rowing")
                            Text("• Walking - For beginners, start with lighter exercises like brisk walking, and gradually increase intensity as your fitness improves")
                        }
                    }
                    
                    InfoSection(imageName: "smartwatch", title: "Do I need a heart rate monitor?") {
                        Text("You can do the Norwegian 4x4 protocol without a heart rate monitor. Just push yourself as hard as you can sustain for 4 minutes at a time. If you push yourself hard enough, you should not be able to speak during the intense intervals. However, if you do have a heart rate monitor you can get more precise—see the next section.")
                    }
                    
                    InfoSection(imageName: "heart", title: "How to Calculate Your Maximum Heart Rate") {
                        Text("To determine your maximum heart rate (MHR), use the following formula:")
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• Subtract your age from 220 (e.g., if you're 40 years old, 220 - 40 = 180). Your MHR is 180 beats per minute (BPM).")
                            Text("• For Norwegian 4x4, aim for 85-95% of your MHR during the 4-minute high-intensity intervals. In this example, that would be between 153 and 171 BPM.")
                            Text("• During the recovery periods, your heart rate should drop to around 60-70% of your MHR (e.g., 108-126 BPM).")
                        }
                    }
                    
                    Text("Download N4x4 now and make the best investment in your health for only 30 minutes per week.")
                        .font(.system(size: 16))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal)
                    
                    // Download Button
                    Button(action: {
                        // Open App Store link
                        if let url = URL(string: "https://apps.apple.com/app/n4x4/id6686407796") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Image("download-on-the-app-store")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250)
                    }
                    
                    // Footer
                    VStack {
                        Text("© 2024 Jan van Rensburg. All rights reserved.")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            // Open Privacy Policy
                            if let url = URL(string: "privacy.txt") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Privacy Policy")
                                .font(.system(size: 14))
                                .underline()
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                .foregroundColor(.white)
            }
        }
    }
}
    // InfoSection View
    struct InfoSection<Content: View>: View {
        var imageName: String
        var title: String
        @ViewBuilder var content: () -> Content
        
        var body: some View {
            VStack {
                HStack(alignment: .top, spacing: 20) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                        content()
                            .font(.system(size: 16))
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
    }

    // Preview Provider
    struct HelpView_Previews: PreviewProvider {
        static var previews: some View {
            HelpView()
                .previewDevice("iPhone 12")
        }
    }
