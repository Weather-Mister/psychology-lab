import SwiftUI

@main
struct GrainlightApp: App {
    @StateObject private var library = PhotoLibrary()
    @AppStorage("autoExport") private var autoExport = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.83, green: 0.72, blue: 0.56))
        }
    }
}
