import SwiftUI

struct RecorderView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var permissionDenied = false
    @State private var showDeck = false
    @State private var showSecondary = false

    private var deck: [BackgroundImage] { state.cachedBackgrounds }
    private var current: BackgroundImage? {
        guard deck.indices.contains(index) else { return deck.first }
        return deck[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewView(camera: state.camera)
                .ignoresSafeArea()
                .gesture(swipeGesture)
                .onTapGesture(count: 2) { if let c = current { state.toggleStar(c.id) } }
                .onLongPressGesture { showDeck = true }

            VStack {
                topBar
                Spacer()
                infoOverlay
                controlBar
            }
            .padding()

            if permissionDenied { permissionOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .task { await setup() }
        .onDisappear { teardown() }
        .sheet(isPresented: $showDeck) { miniDeck }
        .sheet(isPresented: $showSecondary) { secondaryControls }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").padding(10).background(.black.opacity(0.4), in: Circle())
            }
            Spacer()
            if state.camera.isRecording {
                Label(timeString, systemImage: "record.circle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            Spacer()
            Button { showSecondary = true } label: {
                Image(systemName: "slider.horizontal.3").padding(10).background(.black.opacity(0.4), in: Circle())
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Info overlay

    @ViewBuilder private var infoOverlay: some View {
        if let bg = current {
            VStack(spacing: 4) {
                Text(bg.title.isEmpty ? bg.id : bg.title).font(.headline)
                if state.settings.showCaptionOverlay, let caption = bg.caption, !caption.isEmpty {
                    Text(caption).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                if state.settings.showPrivateNotesDuringRecording, let notes = bg.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.yellow)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.bottom, 8)
        }
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 28) {
            controlButton("chevron.left") { step(-1) }
            recordButton
            controlButton("chevron.right") { step(1) }
            controlButton("square.grid.2x2") { showDeck = true }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: state.camera.isRecording ? 6 : 30)
                    .fill(.red)
                    .frame(width: state.camera.isRecording ? 32 : 62,
                           height: state.camera.isRecording ? 32 : 62)
                    .animation(.easeInOut(duration: 0.2), value: state.camera.isRecording)
            }
        }
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 54, height: 54)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    // MARK: Mini deck

    private var miniDeck: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(Array(deck.enumerated()), id: \.element.id) { i, bg in
                        Button {
                            index = i
                            state.selectBackground(bg)
                            showDeck = false
                        } label: {
                            CachedThumbnail(fileName: bg.localFileName)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(i == index ? Color.accentColor : .clear, lineWidth: 3))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose background")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Secondary controls

    private var secondaryControls: some View {
        NavigationStack {
            Form {
                Picker("Crop mode", selection: Binding(
                    get: { state.settings.defaultCropMode },
                    set: { v in state.updateSettings { $0.defaultCropMode = v } })) {
                    ForEach(CropMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Segmentation", selection: Binding(
                    get: { state.settings.segmentationQuality },
                    set: { v in state.updateSettings { $0.segmentationQuality = v } })) {
                    ForEach(SegmentationQuality.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Mirror preview", isOn: Binding(
                    get: { state.settings.mirrorPreview },
                    set: { v in state.updateSettings { $0.mirrorPreview = v }; state.camera.setMirror(v) }))
                Toggle("Caption overlay", isOn: Binding(
                    get: { state.settings.showCaptionOverlay },
                    set: { v in state.updateSettings { $0.showCaptionOverlay = v } }))
                Toggle("Notes during recording", isOn: Binding(
                    get: { state.settings.showPrivateNotesDuringRecording },
                    set: { v in state.updateSettings { $0.showPrivateNotesDuringRecording = v } }))
                if let bg = current {
                    Section("Current image") {
                        Button("Mark used") { state.markUsed(bg.id) }
                        Button(bg.status == .starred ? "Unstar" : "Star") { state.toggleStar(bg.id) }
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: Permission overlay

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Camera or microphone access is off.")
                .multilineTextAlignment(.center)
            Text("Enable it in Settings → Privacy & Security → Camera/Microphone → GreenDeck.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    // MARK: Actions

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.width < -40 { step(1) }
                else if value.translation.width > 40 { step(-1) }
            }
    }

    private func step(_ delta: Int) {
        guard !deck.isEmpty else { return }
        index = (index + delta + deck.count) % deck.count
        if let c = current { state.selectBackground(c) }
    }

    private func toggleRecording() {
        if state.camera.isRecording {
            let bgID = current?.id ?? ""
            state.camera.stopRecording(backgroundID: bgID) { segment in
                if let segment { state.appendSegment(segment) }
            }
        } else {
            state.camera.startRecording(includeAudio: state.settings.microphoneEnabled)
        }
    }

    private var timeString: String {
        let s = Int(state.camera.recordingSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func setup() async {
        let cam = await Permissions.requestCamera()
        var mic = true
        if state.settings.microphoneEnabled { mic = await Permissions.requestMicrophone() }
        guard cam && (mic || !state.settings.microphoneEnabled) else {
            permissionDenied = true
            return
        }
        state.camera.apply(settings: state.settings)

        // Pick the current background (the one already selected, or the first cached).
        if let selectedID = state.camera.currentBackgroundID,
           let i = deck.firstIndex(where: { $0.id == selectedID }) {
            index = i
        } else if let first = deck.first {
            index = 0
            state.selectBackground(first)
        }
        state.camera.start()
    }

    private func teardown() {
        if state.camera.isRecording {
            state.camera.stopRecording(backgroundID: current?.id ?? "") { segment in
                if let segment { state.appendSegment(segment) }
            }
        }
        state.camera.stop()
    }
}
