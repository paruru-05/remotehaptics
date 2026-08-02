import SwiftUI

@main
struct RemoteHapticsApp: App {
    @StateObject private var model = RemoteHapticsModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
