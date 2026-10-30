import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var edits: PhotoEdits = .signature
    @State private var preview: UIImage?
    @State private var isDeveloping = false
    @State private var selectedPanel: EditorPanel = .tone
    @State private var renderTask: Task<Void, Never>?
    @State private var initialized = false
    @State private var previewGeneration = UUID()

    private enum EditorPanel: String, CaseIterable, Identifiable {
        case tone = "Tone", color = "Color", texture = "Texture", crop = "Crop"
        var id: Self { self }
        var icon: String {
            switch self {
            case .tone: return "circle.lefthalf.filled"
            case .color: return "paintpalette"
            case .texture: return "circle.dotted"
            case .crop: return "crop.rotate"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                VStack(spacing: 2) {
                    Text("TUNE YOUR SHOT").font(.system(size: 12, weight: .bold))
                    Text("NON-DESTRUCTIVE").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button("Done") {
                    library.update(id, edits: edits)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView("Developing…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if isDeveloping { ProgressView().scaleEffect(0.7).padding(16) }
            }
            .background(Color.black)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Circle().fill(edits.useLook ? Color(red: 0.85, green: 0.73, blue: 0.56) : .gray)
                            .frame(width: 7, height: 7)
                        Text("SIGNATURE LOOK")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    Toggle("Signature look", isOn: $edits.useLook)
                        .labelsHidden()
                        .scaleEffect(0.8, anchor: .trailing)
                        .tint(Color(red: 0.84, green: 0.72, blue: 0.53))
                }
                .padding(.horizontal, 20)
                .frame(height: 42)

                HStack(spacing: 0) {
                    ForEach(EditorPanel.allCases) { panel in
                        Button { withAnimation(.easeInOut(duration: 0.18)) { selectedPanel = panel } } label: {
                            VStack(spacing: 6) {
                                Image(systemName: panel.icon).font(.system(size: 19, weight: .light))
                                Text(panel.rawValue).font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(selectedPanel == panel ? .white : .white.opacity(0.43))
                            .frame(maxWidth: .infinity)
                            .frame(height: 61)
                            .overlay(alignment: .bottom) {
                                if selectedPanel == panel {
                                    Rectangle().fill(Color(red: 0.83, green: 0.71, blue: 0.56))
                                        .frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().overlay(.white.opacity(0.15))
                ScrollView {
                    VStack(spacing: 14) {
                        switch selectedPanel {
                        case .tone: toneControls
                        case .color: colorControls
                        case .texture: textureControls
                        case .crop: cropControls
                        }
                    }
                    .padding(.horizontal, 23)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                }
                .frame(height: 230)
                HStack {
                    Button("Reset") { edits = .signature }
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("ORIGINAL FILE PRESERVED")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 22)
                .frame(height: 44)
            }
            .background(Color(white: 0.065))
        }
        .background(.black)
        .onAppear {
            guard !initialized, let record = library.record(id) else { return }
            initialized = true
            edits = record.edits
            schedulePreview()
        }
        .onChange(of: edits) { _, _ in schedulePreview() }
        .onDisappear { renderTask?.cancel() }
    }

    @ViewBuilder private var toneControls: some View {
        SliderRow("Exposure", value: $edits.exposure, range: -3...3, unit: "EV")
        SliderRow("Contrast", value: $edits.contrast, range: 0.5...1.5)
        SliderRow("Highlights", value: $edits.highlights, range: -1...1)
        SliderRow("Shadows", value: $edits.shadows, range: -1...1)
        SliderRow("Black point", value: $edits.blacks, range: 0...1)
    }
    @ViewBuilder private var colorControls: some View {
        SliderRow("Warmth", value: $edits.warmth, range: -1...1)
        SliderRow("Tint", value: $edits.tint, range: -1...1)
        SliderRow("Saturation", value: $edits.saturation, range: 0...2)
    }
    @ViewBuilder private var textureControls: some View {
        SliderRow("Grain strength", value: $edits.grain, range: 0...2)
        SliderRow("Grain size", value: $edits.grainSize, range: 0.5...2.5)
        Toggle("Force pixel-size grain", isOn: $edits.forcePixelGrain)
            .font(.system(size: 12)).tint(Color(red: 0.83, green: 0.71, blue: 0.56))
        SliderRow("Halation", value: $edits.halation, range: 0...1.5)
        SliderRow("Halation radius", value: $edits.halationSize, range: 3...36)
        SliderRow("Sharpness", value: $edits.sharpen, range: 0...1)
    }

    @ViewBuilder private var cropControls: some View {
        Text("ASPECT RATIO")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(CropAspect.allCases) { aspect in
            Button {
                edits.crop = aspect
            } label: {
                HStack {
                    Text(aspect.rawValue)
                    Spacer()
                    if edits.crop == aspect { Image(systemName: "checkmark") }
                }
                .font(.system(size: 13))
                .padding(.vertical, 5)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func schedulePreview() {
        guard let record = library.record(id) else { return }
        renderTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        isDeveloping = true
        let source = library.sourceURL(for: record)
        let snapshot = edits
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled else { return }
            let updated = await Task.detached(priority: .userInitiated) {
                FilmRenderer.shared.renderPreview(url: source, edits: snapshot, maxDimension: 1350)
            }.value
            guard !Task.isCancelled, previewGeneration == generation else { return }
            preview = updated
            isDeveloping = false
            if updated == nil { library.lastError = "Could not develop this image. The original is preserved." }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "") {
        self.title = title
        self._value = value
        self.range = range
        self.unit = unit
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(String(format: "%+.2f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: range)
                .tint(Color(red: 0.82, green: 0.71, blue: 0.55))
                .accessibilityLabel(title)
        }
    }
}
