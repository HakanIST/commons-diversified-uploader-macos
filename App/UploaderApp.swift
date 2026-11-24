import SwiftUI

@main
struct UploaderApp: App {
    @StateObject private var model = AppModel()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(model)
                    .opacity(showSplash ? 0 : 1)
                if showSplash {
                    SplashView { withAnimation(.easeInOut(duration: 0.6)) { showSplash = false } }
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .frame(minWidth: 1180, minHeight: 760)
            .task {
                #if DEBUG
                DebugSnapshot.scheduleIfRequested()
                #endif
                await model.restore()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) { Button("Klasör Aç…") { model.chooseFolder() }.keyboardShortcut("o") } }
    }
}
