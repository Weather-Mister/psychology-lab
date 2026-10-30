import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoExport") private var autoExport = false
    @AppStorage("exportFormat") private var exportFormat = "JPEG"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 34, weight: .ultraLight))
                            .frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Grainlight").font(.system(size: 20, weight: .semibold))
                            Text("A camera for deliberate photographs.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("EXPORT") {
                    Toggle("Auto-export new photographs", isOn: $autoExport)
                    Picker("Export format", selection: $exportFormat) {
                        Text("JPEG").tag("JPEG")
                        Text("HEIC").tag("HEIC")
                    }
                    Text("When enabled, developed photographs are copied to Apple Photos. RAW originals always remain in the app's private gallery.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("HOW IT WORKS") {
                    Label("Capture Bayer RAW when supported; otherwise ProRAW or JPEG", systemImage: "camera.metering.matrix")
                    Label("Our own filmic tone and color math", systemImage: "circle.lefthalf.filled")
                    Label("Adjustments never overwrite the source", systemImage: "square.stack")
                    Label("Import DNG images from Files", systemImage: "square.and.arrow.down")
                }
                Section("ABOUT") {
                    Text("Grainlight is an independent demonstration project. It is not affiliated with Chromagraph, Chromatic Applications, Rian Johnson, Steve Yedlin, or Eric Cameron. Its image processing uses independent mathematical approximations, not their proprietary pipeline.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Version 0.1 · iOS 17+")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
