import SwiftUI
import AppKit

@main
struct PaperLensApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            Button {
                appState.toggleMonitoring()
            } label: {
                HStack {
                    Image(systemName: appState.isMonitoringEnabled
                          ? "text.bubble.fill"
                          : "text.bubble")
                    Text(appState.isMonitoringEnabled ? "暂停翻译模式" : "启用翻译模式")
                }
            }

            Divider()

            SettingsLink {
                Text("设置...")
            }

            Divider()

            Button("退出 PaperLens") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            let icon = appState.isMonitoringEnabled ? "text.bubble.fill" : "text.bubble"
            Image(systemName: icon)
                .foregroundColor(appState.isMonitoringEnabled ? .accentColor : .secondary)
        }

        Settings {
            SettingsView()
                .frame(width: 380, height: 330)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @AppStorage("isMonitoringEnabled") var isMonitoringEnabled: Bool = false {
        didSet { updateMonitoring() }
    }
    @AppStorage("autoTranslateSelectedText") private var autoTranslateSelectedText: Bool = true

    private let textMonitor = TextMonitor()
    private let translator = TranslatorService.shared
    private let clipboardDetector = ClipboardDetector()
    private var globalEventMonitor: Any?
    private var clickOutsideMonitor: Any?

    private var buttonWindow: NSPanel?
    private var bubbleWindow: NSPanel?
    private var buttonDismissTimer: Timer?
    private var currentTranslationText: String?
    private var currentBubbleAnchor: NSPoint = .zero

    init() {
        ProcessInfo.processInfo.disableSuddenTermination()
        setupKeyboardShortcut()
        setupAppTermination()
        setupWakeHandler()
        setupClipboardDetector()
        showWelcomeIfNeeded()

        if isMonitoringEnabled {
            startTextMonitor()
        }
    }

    private func showWelcomeIfNeeded() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    private func updateMonitoring() {
        if isMonitoringEnabled {
            startTextMonitor()
        } else {
            stopTextMonitor()
        }
    }

    private func startTextMonitor() {
        textMonitor.onTextSelected = { [weak self] text, bounds in
            self?.handleTextSelected(text: text, bounds: bounds)
        }
        textMonitor.startMonitoring()
        clipboardDetector.start()
    }

    private func stopTextMonitor() {
        textMonitor.stopMonitoring()
        clipboardDetector.stop()
        dismissAllWindows()
    }

    private func handleTextSelected(text: String, bounds: NSRect) {
        let isFullScreen = isFrontmostFullScreen()
        if !isMonitoringEnabled { return }
        if isFullScreen { return }
        dismissAllWindows()
        if autoTranslateSelectedText {
            let position = PositionCalculator.positionForButton(near: bounds)
            translate(text, near: position)
        } else {
            showFloatingButton(at: bounds, text: text)
        }
    }

    // MARK: - Button Window

    private func showFloatingButton(at bounds: NSRect, text: String) {
        let position = PositionCalculator.positionForButton(near: bounds)

        let view = FloatingButtonView {
            self.handleButtonTapped(text: text, buttonPosition: position)
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = NSSize(width: 44, height: 44)

        let window = makeFloatingWindow(contentView: hostingView, at: position, size: hostingView.frame.size)
        buttonWindow = window
        window.orderFront(nil)

        buttonDismissTimer?.invalidate()
        buttonDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissButton()
            }
        }
    }

    private func handleButtonTapped(text: String, buttonPosition: NSPoint) {
        translate(text, near: buttonPosition)
    }

    private func translate(_ text: String, near point: NSPoint) {
        currentTranslationText = text
        dismissButton()
        currentBubbleAnchor = point
        showBubble(state: .streaming(""), near: point)

        let apiKey = KeychainManager.load() ?? ""
        let model = UserDefaults.standard.string(forKey: "deepseekModel") ?? "deepseek-chat"

        var accumulated = ""
        translator.translateStream(
            text,
            apiKey: apiKey,
            model: model,
            onToken: { [weak self] delta in
                accumulated += delta
                self?.updateBubble(state: .streaming(accumulated))
            },
            onComplete: { [weak self] result in
                switch result {
                case .success(let final):
                    self?.updateBubble(state: .result(final))
                case .failure(let error):
                    self?.updateBubble(state: .error(error.localizedDescription))
                }
            }
        )
    }

    private func dismissButton() {
        buttonDismissTimer?.invalidate()
        buttonDismissTimer = nil
        buttonWindow?.close()
        buttonWindow = nil
    }

    // MARK: - Bubble Window

    private func showBubble(state: BubbleState, near point: NSPoint) {
        dismissBubble()
        currentBubbleAnchor = point

        let bubblePosition = PositionCalculator.positionForBubble(near: point)
        let view = makeBubbleView(state: state)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = NSSize(width: 520, height: 320)
        hostingView.autoresizingMask = [.width, .height]

        let window = makeFloatingWindow(contentView: hostingView, at: bubblePosition, size: hostingView.frame.size, resizable: true)
        window.setContentSize(NSSize(width: 520, height: 320))
        window.isMovableByWindowBackground = true
        window.initialFirstResponder = nil
        bubbleWindow = window
        window.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.bubbleWindow != nil else { return }
            self.clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self, let bubble = self.bubbleWindow else { return }
                let clickPoint = NSEvent.mouseLocation
                if !NSPointInRect(clickPoint, bubble.frame) {
                    DispatchQueue.main.async {
                        self.dismissBubble()
                    }
                }
            }
        }
    }

    private func updateBubble(state: BubbleState) {
        guard let hostingView = bubbleWindow?.contentView as? NSHostingView<TranslationBubbleView> else {
            showBubble(state: state, near: currentBubbleAnchor)
            return
        }
        hostingView.rootView = makeBubbleView(state: state)
        bubbleWindow?.orderFront(nil)
    }

    private func dismissBubble() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        bubbleWindow?.close()
        bubbleWindow = nil
    }

    private func makeBubbleView(state: BubbleState) -> TranslationBubbleView {
        TranslationBubbleView(
            state: state,
            onCopy: { [weak self] text in
                self?.copyTranslation(text)
            },
            onDismiss: { [weak self] in
                self?.dismissBubble()
            },
            onRetry: { [weak self] in
                guard let self = self, let text = self.currentTranslationText else { return }
                self.translate(text, near: self.currentBubbleAnchor)
            }
        )
    }

    private func dismissAllWindows() {
        dismissButton()
        dismissBubble()
        translator.cancelCurrent()
    }

    private func copyTranslation(_ text: String) {
        clipboardDetector.suppressClipboardChanges(for: 1.2)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        clipboardDetector.suppressClipboardChanges(for: 1.2)
    }

    // MARK: - Window Factory

    private func makeFloatingWindow(contentView: NSView, at point: NSPoint, size: NSSize, resizable: Bool = false) -> NSPanel {
        var styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if resizable { styleMask.insert(.resizable) }

        let panel = NSPanel(
            contentRect: NSRect(origin: point, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = contentView
        panel.hidesOnDeactivate = false
        if resizable {
            panel.minSize = NSSize(width: 320, height: 160)
        }
        return panel
    }

    private func isMouseInsideFloatingUI() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        if let buttonWindow, NSPointInRect(mouseLocation, buttonWindow.frame) {
            return true
        }
        if let bubbleWindow, NSPointInRect(mouseLocation, bubbleWindow.frame) {
            return true
        }
        return false
    }

    // MARK: - Full Screen Detection

    private var lastFullScreenCheck: (Date, Bool)?
    private func isFrontmostFullScreen() -> Bool {
        if let (date, result) = lastFullScreenCheck, -date.timeIntervalSinceNow < 0.5 {
            return result
        }

        guard let screen = NSScreen.main else { return false }
        let screenBounds = screen.frame

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var maxCoverage: CGFloat = 0
        for info in windowList {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat else { continue }

            let windowRect = NSRect(x: x, y: y, width: w, height: h)
            let intersection = screenBounds.intersection(windowRect)
            let coverage = (intersection.width * intersection.height) / (screenBounds.width * screenBounds.height)

            if coverage > maxCoverage { maxCoverage = coverage }
        }

        let result = maxCoverage > 0.95
        lastFullScreenCheck = (Date(), result)
        return result
    }

    // MARK: - Keyboard Shortcut

    private func setupKeyboardShortcut() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "t" {
                DispatchQueue.main.async {
                    self?.toggleMonitoring()
                }
            }
        }
    }

    private func setupAppTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.textMonitor.stopMonitoring()
                self.clipboardDetector.stop()
                self.dismissAllWindows()
                if let monitor = self.globalEventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }

    private func setupWakeHandler() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard self.isMonitoringEnabled else { return }
                self.textMonitor.stopMonitoring()
                self.clipboardDetector.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if self.isMonitoringEnabled {
                        self.textMonitor.startMonitoring()
                        self.clipboardDetector.start()
                    }
                }
            }
        }
    }

    private func setupClipboardDetector() {
        clipboardDetector.isFrontmostTerminal = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return false }
            return Self.terminalBundleIDs.contains(app.bundleIdentifier ?? "")
        }
        clipboardDetector.shouldIgnoreMouseUp = { [weak self] in
            self?.isMouseInsideFloatingUI() ?? false
        }
        clipboardDetector.shouldSkipAutoCopy = { [weak self] in
            guard let self = self else { return true }
            return self.buttonWindow != nil || self.bubbleWindow != nil
        }
        clipboardDetector.onTextDetected = { [weak self] (text: String) in
            guard let self = self,
                  self.isMonitoringEnabled,
                  self.buttonWindow == nil,
                  self.bubbleWindow == nil else { return }
            self.handleClipboardText(text)
        }
    }

    private func handleClipboardText(_ text: String) {
        guard !isFrontmostFullScreen() else { return }
        let mouseLocation = NSEvent.mouseLocation
        let bounds = NSRect(x: mouseLocation.x - 50, y: mouseLocation.y - 10, width: 100, height: 20)
        if autoTranslateSelectedText {
            translate(text, near: PositionCalculator.positionForButton(near: bounds))
        } else {
            showFloatingButton(at: bounds, text: text)
        }
    }

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable"
    ]

    deinit {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
