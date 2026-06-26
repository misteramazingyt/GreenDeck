import SwiftUI

private enum EditTarget {
    case none, person, background
}

struct RecorderView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var permissionDenied = false
    @State private var showDeck = false
    @State private var showSecondary = false

    // Layer editing
    @State private var editTarget: EditTarget = .none
    @State private var personScale: CGFloat = 1
    @State private var personOffset: CGSize = .zero
    @State private var bgScale: CGFloat = 1
    @State private var bgOffset: CGSize = .zero
    // Gesture anchors
    @State private var dragStart: CGSize?
    @State private var scaleStart: CGFloat?
    // Multi-tap detection (2 taps = edit YOU, 3 taps = edit background)
    @State private var tapCount = 0
    @State private var tapResetWork: DispatchWorkItem?

    private var deck: [BackgroundImage] { state.cachedBackgrounds }
    private var current: BackgroundImage? {
        guard deck.indices.contains(index) else { return deck.first }
        return deck[index]
    }

    var body: some View {
        GeometryReader { geo in
            let displayed = displayedSize(geo.size)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreviewView(camera: state.camera)
                    .ignoresSafeArea()

                // Gesture surface
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { v in
                                guard editTarget != .none else { return }
                                if dragStart == nil { dragStart = activeOffset() }
                                let base = dragStart ?? .zero
                                setActiveOffset(CGSize(width: base.width + v.translation.width,
                                                       height: base.height + v.translation.height))
                                if editTarget == .background { markCustom() }
                                push(displayed)
                            }
                            .onEnded { v in
                                if editTarget == .none {
                                    if v.translation.width < -40 { step(1) }
                                    else if v.translation.width > 40 { step(-1) }
                                }
                                dragStart = nil
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { m in
                                guard editTarget != .none else { return }
                                if scaleStart == nil { scaleStart = activeScale() }
                                let base = scaleStart ?? 1
                                setActiveScale(min(max(base * m, 0.2), 5))
                                if editTarget == .background { markCustom() }
                                push(displayed)
                            }
                            .onEnded { _ in scaleStart = nil }
                    )
                    .onTapGesture { registerTap() }
                    .onLongPressGesture { showDeck = true }

                if editTarget != .none {
                    boundingBox(displayed: displayed, center: center)
                }

                VStack {
                    topBar
                    Spacer()
                    if editTarget != .none { editHint }
                    infoOverlay
                    controlBar
                }
                .padding()

                if permissionDenied { permissionOverlay }
            }
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
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .opacity(state.camera.isPaused ? 0.3 : 1)
                        Text(timeString(state.camera.recordingSeconds)).monospacedDigit()
                    }
                    if state.camera.isPaused {
                        Text("PAUSED").font(.caption2).bold()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Button { showSecondary = true } label: {
                Image(systemName: "slider.horizontal.3").padding(10).background(.black.opacity(0.4), in: Circle())
            }
        }
        .foregroundStyle(.white)
    }

    private var editHint: some View {
        Text(editTarget == .person
             ? "Editing YOU — drag to move, pinch to scale. Double-tap to lock."
             : "Editing BACKGROUND — drag to move, pinch to scale. Triple-tap to lock.")
            .font(.caption).foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 6)
    }

    // MARK: Info overlay

    @ViewBuilder private var infoOverlay: some View {
        if let bg = current, editTarget == .none {
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
        HStack(spacing: 22) {
            controlButton("chevron.left") { step(-1) }
            if state.camera.isRecording {
                pauseButton
                stopButton
            } else {
                recordButton
            }
            controlButton("chevron.right") { step(1) }
            controlButton("square.grid.2x2") { showDeck = true }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private var recordButton: some View {
        Button { startRecording() } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(.red).frame(width: 62, height: 62)
            }
        }
    }

    private var stopButton: some View {
        Button { stopRecording() } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 32, height: 32)
            }
        }
    }

    private var pauseButton: some View {
        Button { togglePause() } label: {
            Image(systemName: state.camera.isPaused ? "play.fill" : "pause.fill")
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
        }
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    // MARK: Bounding box

    private func boundingBox(displayed: CGSize, center: CGPoint) -> some View {
        let s = activeScale()
        let o = activeOffset()
        let color: Color = editTarget == .person ? .green : .yellow
        return Rectangle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .frame(width: displayed.width * s, height: displayed.height * s)
            .overlay(
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(color).frame(width: 12, height: 12)
                        .position(
                            x: i % 2 == 0 ? 0 : displayed.width * s,
                            y: i < 2 ? 0 : displayed.height * s
                        )
                }
            )
            .position(x: center.x + o.width, y: center.y + o.height)
            .allowsHitTesting(false)
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
                    set: { v in
                        state.updateSettings { $0.defaultCropMode = v }
                        if v != .custom { resetBackgroundFraming() }
                    })) {
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

                Section("Framing") {
                    Button("Reset YOU") { resetPersonFraming() }
                    Button("Reset background") { resetBackgroundFraming() }
                }
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
        .presentationDetents([.medium, .large])
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

    // MARK: Editing helpers

    /// Debounced multi-tap: 2 taps edit YOU, 3 taps edit the background.
    private func registerTap() {
        tapCount += 1
        tapResetWork?.cancel()
        let work = DispatchWorkItem {
            if tapCount == 2 { toggle(.person) }
            else if tapCount >= 3 { toggle(.background) }
            tapCount = 0
        }
        tapResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func toggle(_ target: EditTarget) {
        editTarget = (editTarget == target) ? .none : target
        dragStart = nil
        scaleStart = nil
    }

    private func activeOffset() -> CGSize { editTarget == .person ? personOffset : bgOffset }
    private func setActiveOffset(_ o: CGSize) {
        if editTarget == .person { personOffset = o } else { bgOffset = o }
    }
    private func activeScale() -> CGFloat { editTarget == .person ? personScale : bgScale }
    private func setActiveScale(_ s: CGFloat) {
        if editTarget == .person { personScale = s } else { bgScale = s }
    }

    private func markCustom() {
        if state.settings.defaultCropMode != .custom {
            state.updateSettings { $0.defaultCropMode = .custom }
        }
    }

    /// Convert point-space scale/offset into composite-pixel transforms.
    private func push(_ displayed: CGSize) {
        let outW = state.settings.outputResolution.pixelSize.width
        let ppx = outW / max(displayed.width, 1)
        state.camera.setPersonTransform(LayerTransform(
            scale: personScale,
            offsetX: personOffset.width * ppx,
            offsetY: -personOffset.height * ppx))
        state.camera.setBackgroundTransform(LayerTransform(
            scale: bgScale,
            offsetX: bgOffset.width * ppx,
            offsetY: -bgOffset.height * ppx))
    }

    private func resetPersonFraming() {
        personScale = 1; personOffset = .zero
        state.camera.setPersonTransform(.identity)
    }
    private func resetBackgroundFraming() {
        bgScale = 1; bgOffset = .zero
        state.camera.setBackgroundTransform(.identity)
    }

    private func displayedSize(_ viewSize: CGSize) -> CGSize {
        let out = state.settings.outputResolution.pixelSize
        guard out.width > 0, out.height > 0 else { return viewSize }
        let scale = min(viewSize.width / out.width, viewSize.height / out.height)
        return CGSize(width: out.width * scale, height: out.height * scale)
    }

    // MARK: Recording actions

    private func startRecording() {
        state.camera.startRecording(includeAudio: state.settings.microphoneEnabled)
    }

    private func togglePause() {
        if state.camera.isPaused { state.camera.resumeRecording() }
        else { state.camera.pauseRecording() }
    }

    private func stopRecording() {
        let bgID = current?.id ?? ""
        state.camera.stopRecording(backgroundID: bgID) { segment in
            if let segment { state.appendSegment(segment) }
        }
    }

    // MARK: Background navigation

    private func step(_ delta: Int) {
        guard !deck.isEmpty else { return }
        index = (index + delta + deck.count) % deck.count
        if let c = current { state.selectBackground(c) }
    }

    private func timeString(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    // MARK: Lifecycle

    private func setup() async {
        let cam = await Permissions.requestCamera()
        var mic = true
        if state.settings.microphoneEnabled { mic = await Permissions.requestMicrophone() }
        guard cam && (mic || !state.settings.microphoneEnabled) else {
            permissionDenied = true
            return
        }
        state.camera.apply(settings: state.settings)

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
