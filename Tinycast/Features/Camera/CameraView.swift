import AppKit
@preconcurrency import AVFoundation
import Carbon.HIToolbox
import SwiftUI

private enum CameraState: Equatable {
    case requestingPermission
    case starting
    case ready
    case denied
    case unavailable
    case failed(String)
}

private struct CameraDevice: Equatable, Sendable {
    let id: String
    let name: String
}

private struct CameraKeyboardEvent: Equatable {
    enum Command {
        case activate
        case moveUp
        case moveDown
        case toggleActions
        case toggleMirroring
        case showCameras
        case escape
    }

    let id = UUID()
    let command: Command
}

private enum CameraCaptureError: Error, Sendable {
    case deviceUnavailable
    case inputUnavailable
    case outputUnavailable
    case captureUnavailable
    case processingFailed

    var message: String {
        switch self {
        case .deviceUnavailable: return "The selected camera is no longer available."
        case .inputUnavailable: return "Tinycast couldn't connect to this camera."
        case .outputUnavailable: return "This camera doesn't support photo capture."
        case .captureUnavailable: return "The camera isn't ready to take a photo."
        case .processingFailed: return "Tinycast couldn't process the captured photo."
        }
    }
}

/// Serializes all capture-session mutations away from the main actor.
private final class CameraCaptureEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.tinycast.camera-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var captureCompletion:
        (@Sendable (Result<Data, CameraCaptureError>) -> Void)?

    static func availableDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: .video)?.uniqueID
        var seen = Set<String>()
        return discovery.devices
            .filter { seen.insert($0.uniqueID).inserted }
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted {
                if $0.id == defaultID { return true }
                if $1.id == defaultID { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func start(
        deviceID: String,
        completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in
            switch configure(deviceID: deviceID) {
            case .success:
                if !session.isRunning { session.startRunning() }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func switchDevice(
        to deviceID: String,
        completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in
            completion(configure(deviceID: deviceID))
        }
    }

    func capture(
        mirrored: Bool,
        completion: @escaping @Sendable (Result<Data, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in
            guard session.isRunning, captureCompletion == nil,
                let connection = photoOutput.connection(with: .video)
            else {
                completion(.failure(.captureUnavailable))
                return
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            captureCompletion = completion
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            captureCompletion = nil
        }
    }

    private func configure(deviceID: String) -> Result<Void, CameraCaptureError> {
        guard
            let device = Self.captureDevices().first(where: { $0.uniqueID == deviceID })
        else {
            return .failure(.deviceUnavailable)
        }
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: device)
        } catch {
            return .failure(.inputUnavailable)
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }

        let previousInput = currentInput
        if let previousInput { session.removeInput(previousInput) }
        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            return .failure(.inputUnavailable)
        }
        session.addInput(newInput)
        currentInput = newInput

        if !session.outputs.contains(where: { $0 === photoOutput }) {
            guard session.canAddOutput(photoOutput) else {
                session.removeInput(newInput)
                currentInput = nil
                if let previousInput, session.canAddInput(previousInput) {
                    session.addInput(previousInput)
                    currentInput = previousInput
                }
                return .failure(.outputUnavailable)
            }
            photoOutput.isDeferredStartEnabled = false
            session.addOutput(photoOutput)
        }
        return .success(())
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

extension CameraCaptureEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let result: Result<Data, CameraCaptureError>
        if error != nil {
            result = .failure(.processingFailed)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(.processingFailed)
        }
        queue.async { [self] in
            let completion = captureCompletion
            captureCompletion = nil
            completion?(result)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        guard error != nil else { return }
        queue.async { [self] in
            let completion = captureCompletion
            captureCompletion = nil
            completion?(.failure(.processingFailed))
        }
    }
}

@MainActor
private final class CameraSessionModel: ObservableObject {
    @Published private(set) var state: CameraState = .starting
    @Published private(set) var devices: [CameraDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var isCapturing = false
    @Published var isMirrored = true
    @Published private(set) var feedback: String?
    @Published private(set) var flashToken = UUID()
    @Published private(set) var keyboardEvent: CameraKeyboardEvent?

    let session: AVCaptureSession
    private let engine: CameraCaptureEngine
    private var feedbackTask: Task<Void, Never>?

    init() {
        let engine = CameraCaptureEngine()
        self.engine = engine
        session = engine.session
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            discoverAndStart()
        case .notDetermined:
            state = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.discoverAndStart()
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func stop() {
        feedbackTask?.cancel()
        feedbackTask = nil
        engine.stop()
    }

    func takePhoto() {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true
        engine.capture(mirrored: isMirrored) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isCapturing = false
                switch result {
                case .success(let data):
                    guard
                        let png = NSBitmapImageRep(data: data)?
                            .representation(using: .png, properties: [:])
                    else {
                        self.showFeedback(CameraCaptureError.processingFailed.message)
                        return
                    }
                    Paster.copyImage(png)
                    self.flashToken = UUID()
                    self.showFeedback("Photo copied to clipboard")
                case .failure(let error):
                    self.showFeedback(error.message)
                }
            }
        }
    }

    func toggleMirroring() {
        isMirrored.toggle()
        showFeedback(isMirrored ? "Mirroring on" : "Mirroring off")
    }

    func selectCamera(_ device: CameraDevice) {
        guard !isCapturing else { return }
        guard device.id != selectedDeviceID else {
            showFeedback("\(device.name) is already selected")
            return
        }
        guard devices.contains(device) else {
            showFeedback(CameraCaptureError.deviceUnavailable.message)
            return
        }
        state = .starting
        engine.switchDevice(to: device.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.selectedDeviceID = device.id
                    self.state = .ready
                    self.showFeedback("Switched to \(device.name)")
                case .failure(let error):
                    self.state = .failed(error.message)
                }
            }
        }
    }

    func openCameraSettings() {
        Permissions.openCameraSettings()
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let commandDown = event.modifierFlags.contains(.command)
        let keyCode = Int(event.keyCode)
        let command: CameraKeyboardEvent.Command?
        if commandDown {
            switch keyCode {
            case kVK_ANSI_K: command = .toggleActions
            case kVK_ANSI_M: command = .toggleMirroring
            case kVK_ANSI_S: command = .showCameras
            default: command = nil
            }
        } else {
            switch keyCode {
            case kVK_Return, kVK_ANSI_KeypadEnter: command = .activate
            case kVK_UpArrow: command = .moveUp
            case kVK_DownArrow: command = .moveDown
            case kVK_Escape: command = .escape
            default: command = nil
            }
        }
        guard let command else { return false }
        keyboardEvent = CameraKeyboardEvent(command: command)
        return true
    }

    private func discoverAndStart() {
        devices = CameraCaptureEngine.availableDevices()
        guard let device = devices.first else {
            state = .unavailable
            return
        }
        selectedDeviceID = device.id
        state = .starting
        engine.start(deviceID: device.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.state = .ready
                case .failure(let error):
                    self.state = .failed(error.message)
                }
            }
        }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        feedback = text
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }
}

@MainActor
final class CameraWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: CameraPanel?
    private var model: CameraSessionModel?

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let model = CameraSessionModel()
        let panel = CameraPanel(
            rootView: CameraView(model: model) { [weak self] in self?.returnToRoot() })
        panel.onKeyDown = { [weak model] event in
            model?.handleKeyDown(event) ?? false
        }
        panel.delegate = self
        position(panel)
        self.model = model
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
        model.start()
    }

    @discardableResult
    func focusExisting() -> Bool {
        guard let panel else { return false }
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        model?.stop()
        panel?.close()
    }

    private func returnToRoot() {
        close()
        core.showPalette(mode: .launcher)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model = nil
        panel = nil
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let size = CameraPanel.size
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * Theme.Size.paletteTopMarginFraction - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: false)
    }
}

private final class CameraPanel: NSPanel {
    static let size = CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
    var onKeyDown: ((NSEvent) -> Bool)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }
}

private struct CameraView: View {
    private enum MenuLevel: Equatable {
        case actions
        case cameras
    }

    @ObservedObject var model: CameraSessionModel
    let onBack: () -> Void

    @State private var showActions = false
    @State private var menuLevel = MenuLevel.actions
    @State private var menuSelection = 0
    @State private var flashOpacity = 0.0

    private var actionItems: [PopoverMenuItem] {
        [
            PopoverMenuItem(
                title: "Take Photo", systemImage: "camera", shortcut: "↵",
                action: model.takePhoto),
            PopoverMenuItem(
                title: model.isMirrored ? "Turn Mirroring Off" : "Turn Mirroring On",
                systemImage: "arrow.left.and.right", shortcut: "⌘M",
                action: model.toggleMirroring),
            PopoverMenuItem(
                title: "Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera",
                shortcut: "⌘S", action: showCameraChoices),
        ]
    }

    private var cameraItems: [PopoverMenuItem] {
        model.devices.map { device in
            PopoverMenuItem(
                title: device.name,
                systemImage: device.id == model.selectedDeviceID ? "checkmark" : "video",
                action: { model.selectCamera(device) }
            )
        }
    }

    private var menuItems: [PopoverMenuItem] {
        switch menuLevel {
        case .actions: return actionItems
        case .cameras: return cameraItems
        }
    }

    private var menuHeader: String? {
        switch menuLevel {
        case .actions: return selectedDeviceName
        case .cameras: return "Select Camera"
        }
    }

    private var selectedDeviceName: String? {
        guard let id = model.selectedDeviceID else { return nil }
        return model.devices.first(where: { $0.id == id })?.name
    }

    var body: some View {
        ZStack {
            Color.black
            switch model.state {
            case .ready:
                CameraPreview(session: model.session, mirrored: model.isMirrored)
            case .requestingPermission:
                CameraPlaceholder(
                    icon: "video.badge.ellipsis", title: "Camera Access",
                    message: "Allow Tinycast to use your camera in the macOS prompt.")
            case .starting:
                CameraPlaceholder(
                    icon: "camera", title: "Starting Camera",
                    message: selectedDeviceName ?? "Connecting…", showsProgress: true)
            case .denied:
                CameraPlaceholder(
                    icon: "video.slash", title: "Camera Access Is Off",
                    message: "Allow Tinycast in Privacy & Security › Camera.",
                    buttonTitle: "Open System Settings", buttonAction: model.openCameraSettings)
            case .unavailable:
                CameraPlaceholder(
                    icon: "video.slash", title: "No Camera Found",
                    message: "Connect a camera and reopen this command.")
            case .failed(let message):
                CameraPlaceholder(
                    icon: "exclamationmark.triangle", title: "Camera Unavailable",
                    message: message)
            }

            Color.white
                .opacity(flashOpacity)
                .allowsHitTesting(false)

            controls
        }
        .frame(width: CameraPanel.size.width, height: CameraPanel.size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .overlay {
            if showActions {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { closeMenu() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions {
                PopoverMenu(
                    header: menuHeader, items: menuItems, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Size.bottomBarHeight - Theme.Spacing.xs)
                .transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
        }
        .onChange(of: model.flashToken) {
            flashOpacity = 0.7
            withAnimation(.easeOut(duration: 0.22)) { flashOpacity = 0 }
        }
        .onChange(of: model.keyboardEvent) { _, event in
            guard let event else { return }
            handleKeyboard(event.command)
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                CameraOverlayButton(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                Spacer()
            }
            Spacer()
            HStack(alignment: .bottom) {
                CameraStatusPill(
                    deviceName: selectedDeviceName, feedback: model.feedback)
                Spacer()
                cameraActionGroup
            }
        }
        .padding(Theme.Spacing.md)
    }

    private var cameraActionGroup: some View {
        HStack(spacing: 2) {
            CameraBarButton(action: model.takePhoto) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(model.isCapturing ? "Taking Photo…" : "Take Photo")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.primary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            .disabled(model.state != .ready || model.isCapturing)
            CameraBarButton {
                toggleActionsMenu()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Actions")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private func activateMenuItem(_ index: Int) {
        guard menuItems.indices.contains(index) else { return }
        let level = menuLevel
        menuItems[index].action()
        if level != menuLevel { return }
        closeMenu()
    }

    private func handleKeyboard(_ command: CameraKeyboardEvent.Command) {
        switch command {
        case .activate:
            if showActions {
                activateMenuItem(menuSelection)
            } else {
                model.takePhoto()
            }
        case .moveUp:
            guard showActions else { return }
            menuSelection = max(menuSelection - 1, 0)
        case .moveDown:
            guard showActions, !menuItems.isEmpty else { return }
            menuSelection = min(menuSelection + 1, menuItems.count - 1)
        case .toggleActions:
            toggleActionsMenu()
        case .toggleMirroring:
            model.toggleMirroring()
        case .showCameras:
            showCameraChoices()
        case .escape:
            if showActions {
                closeMenu()
            } else {
                onBack()
            }
        }
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.14)) {
            showActions = false
            menuLevel = .actions
        }
        menuSelection = 0
    }

    private func toggleActionsMenu() {
        if showActions {
            closeMenu()
            return
        }
        menuLevel = .actions
        menuSelection = 0
        withAnimation(.easeOut(duration: 0.14)) { showActions = true }
    }

    private func showCameraChoices() {
        guard !model.devices.isEmpty else { return }
        menuLevel = .cameras
        menuSelection =
            model.devices.firstIndex(where: { $0.id == model.selectedDeviceID }) ?? 0
        withAnimation(.easeOut(duration: 0.14)) { showActions = true }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session, mirrored: mirrored)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.setMirrored(mirrored)
    }
}

private final class CameraPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession, mirrored: Bool) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        setMirrored(mirrored)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else {
            return
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}

private struct CameraPlaceholder: View {
    let icon: String
    let title: String
    let message: String
    var showsProgress = false
    var buttonTitle: String?
    var buttonAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let buttonAction {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}

private struct CameraStatusPill: View {
    let deviceName: String?
    let feedback: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(feedback ?? "Open Camera")
                .font(Theme.Typography.bar)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 36)
        .frosted(in: Capsule())
        .help(deviceName ?? "Open Camera")
    }
}

private struct CameraOverlayButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(.primary)
                .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

private struct CameraBarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
