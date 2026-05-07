import AppKit

final class ClipboardDetector {
    var onTextDetected: ((String) -> Void)?
    var isFrontmostTerminal: (() -> Bool)?
    var shouldIgnoreMouseUp: (() -> Bool)?
    var shouldSkipAutoCopy: (() -> Bool)?

    private var mouseMonitor: Any?
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isActive: Bool = false
    private var isCopying: Bool = false
    private var suppressUntil: Date = .distantPast

    func start() {
        guard !isActive else { return }
        isActive = true

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        }

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }

        lastChangeCount = NSPasteboard.general.changeCount
    }

    func stop() {
        isActive = false
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    func suppressClipboardChanges(for seconds: TimeInterval) {
        suppressUntil = Date().addingTimeInterval(seconds)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func handleMouseUp() {
        guard isActive, !isCopying, !(isFrontmostTerminal?() ?? false) else { return }
        if shouldIgnoreMouseUp?() ?? false { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.autoCopy()
        }
    }

    private func autoCopy() {
        guard isActive, !isCopying else { return }
        if shouldSkipAutoCopy?() ?? false { return }
        isCopying = true

        let pb = NSPasteboard.general

        var savedItems: [(NSPasteboard.PasteboardType, Data)] = []
        for type in pb.types ?? [] {
            if let data = pb.data(forType: type) {
                savedItems.append((type, data))
            }
        }

        pb.clearContents()

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "tell application \"System Events\" to keystroke \"c\" using command down"]
        task.launch()
        task.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self = self else { return }

            let newText = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            pb.clearContents()
            if !savedItems.isEmpty {
                let types = savedItems.map(\.0)
                pb.declareTypes(types, owner: nil)
                for (type, data) in savedItems {
                    pb.setData(data, forType: type)
                }
            }

            self.isCopying = false
            self.lastChangeCount = pb.changeCount

            guard !newText.isEmpty,
                  newText.rangeOfCharacter(from: .letters) != nil,
                  newText.count <= 5000 else { return }

            self.onTextDetected?(newText)
        }
    }

    private func checkClipboardChange() {
        guard isActive, !isCopying else { return }

        if Date() < suppressUntil {
            lastChangeCount = NSPasteboard.general.changeCount
            return
        }

        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }

        lastChangeCount = currentCount

        if let text = validText(from: pb) {
            onTextDetected?(text)
            return
        }

        let types = pb.types ?? []
        let hasTextType = types.contains(.string) || types.contains(where: { $0.rawValue == "public.utf8-plain-text" })
        if hasTextType {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                guard let self = self, self.isActive, !self.isCopying else { return }
                if let text = self.validText(from: pb) {
                    self.onTextDetected?(text)
                }
            }
        }
    }

    private func validText(from pb: NSPasteboard) -> String? {
        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.rangeOfCharacter(from: .letters) != nil,
              text.count <= 5000 else { return nil }
        return text
    }
}
