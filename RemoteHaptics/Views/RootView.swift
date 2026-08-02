import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    var body: some View {
        Group {
            if model.connectionState == .connected {
                TabView {
                    TrackpadView()
                        .tabItem { Label("トラックパッド", systemImage: "rectangle.and.hand.point.up.left") }
                    KeyboardView()
                        .tabItem { Label("キーボード", systemImage: "keyboard") }
                    CommandView()
                        .tabItem { Label("コマンド", systemImage: "terminal") }
                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            } else {
                ConnectionView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.connectionState)
    }
}
