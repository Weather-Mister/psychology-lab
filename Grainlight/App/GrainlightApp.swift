import SwiftUI

@main
struct GrainlightApp: App {
    @StateObject private var library = PhotoLibrary()
    @AppStorage("autoExport") private var autoExport = false

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.83, green: 0.72, blue: 0.56))
        }
    }
    @ViewBuilder private var rootView: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--capture-self-test") { CaptureSelfTestView() }
        else { MainView() }
        #else
        MainView()
        #endif
    }
}
