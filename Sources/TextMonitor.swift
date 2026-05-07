import AppKit
import ApplicationServices

@MainActor
final class TextMonitor {
    var onTextSelected: ((String, NSRect) -> Void)?

    private var currentObserver: AXObserver?
    private var currentPID: pid_t = 0
    private var currentFocusedElement: AXUIElement?
    private var workspaceObserver: NSObjectProtocol?
    private var isMonitoring: Bool = false
    private var pollTimer: Timer?
    private var lastPolledText: String?

    func startMonitoring() {
        guard !isMonitoring else { return }

        guard isAccessibilityEnabled() else {
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "PaperLens 需要辅助功能权限来检测文本选中。\n请在系统设置中授权。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }

        isMonitoring = true
        attachToCurrentApp()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard self.isMonitoring else { return }
                self.pollSelectedText()
            }
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard self.isMonitoring else { return }
                self.attachToCurrentApp()
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        detachObserver()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }

    var isActive: Bool { isMonitoring }

    private func attachToCurrentApp() {
        detachObserver()

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        currentPID = pid

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)

        guard result == .success, let obs = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)

        AXObserverAddNotification(
            obs,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        currentObserver = obs
        registerTextSelectionOnFocusedElement(appElement: appElement)

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
    }

    private func registerTextSelectionOnFocusedElement(appElement: AXUIElement) {
        guard let obs = currentObserver else { return }

        registerOnAppElement(obs, appElement: appElement)

        var focusedElement: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return }

        let axElement = element as! AXUIElement
        let result = AXObserverAddNotification(
            obs,
            axElement,
            kAXSelectedTextChangedNotification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if result == .success {
            currentFocusedElement = axElement
        }
    }

    private func registerOnAppElement(_ obs: AXObserver, appElement: AXUIElement) {
        AXObserverAddNotification(
            obs,
            appElement,
            kAXSelectedTextChangedNotification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func detachObserver() {
        if let obs = currentObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(obs),
                .defaultMode
            )
            currentObserver = nil
        }
        currentPID = 0
        currentFocusedElement = nil
    }

    fileprivate func handleAXNotification(element: AXUIElement, notification: CFString) {
        guard isMonitoring else { return }

        let notifStr = notification as String

        if notifStr == kAXFocusedUIElementChangedNotification as String {
            let appElement = AXUIElementCreateApplication(currentPID)
            registerTextSelectionOnFocusedElement(appElement: appElement)
            return
        }

        if notifStr == kAXSelectedTextChangedNotification as String {
            handleSelectionChanged(element: element)
        }
    }

    private func pollSelectedText() {
        guard isMonitoring, let app = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        if let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() {
            let element = f as! AXUIElement
            if let result = tryGetSelectedText(from: element) {
                processPolledText(result.text, element: result.element)
                return
            }
        }

        if let result = tryGetSelectedText(from: appElement) {
            processPolledText(result.text, element: result.element)
            return
        }

        var webArea: CFTypeRef?
        if findWebArea(appElement, &webArea), let wa = webArea, CFGetTypeID(wa) == AXUIElementGetTypeID() {
            let webElement = wa as! AXUIElement
            if let result = tryGetSelectedText(from: webElement) {
                processPolledText(result.text, element: result.element)
                return
            }
            if let childResult = findSelectedTextInImmediateChildren(of: webElement) {
                processPolledText(childResult.text, element: childResult.element)
                return
            }
        }

        lastPolledText = nil
    }

    private func findWebArea(_ element: AXUIElement, _ result: inout CFTypeRef?) -> Bool {
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String, roleStr == "AXWebArea" {
            result = element
            return true
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return false }

        for child in children {
            if findWebArea(child, &result) {
                return true
            }
        }
        return false
    }

    private func findSelectedTextInImmediateChildren(of element: AXUIElement) -> (text: String, element: AXUIElement)? {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }

        for child in children {
            if let r = tryGetSelectedText(from: child) {
                return r
            }
        }
        return nil
    }

    private func tryGetSelectedText(from element: AXUIElement) -> (text: String, element: AXUIElement)? {
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textValue) == .success,
              let text = textValue as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 5000,
              trimmed.rangeOfCharacter(from: .letters) != nil else { return nil }
        return (trimmed, element)
    }

    private func processPolledText(_ text: String, element: AXUIElement) {
        guard text != lastPolledText else { return }
        lastPolledText = text
        let bounds = selectionBounds(element: element)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isMonitoring else { return }
            self.onTextSelected?(text, bounds)
        }
    }

    fileprivate func handleSelectionChanged(element: AXUIElement) {
        guard isMonitoring else { return }

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)

        guard textResult == .success,
              let text = selectedText as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastPolledText = nil
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 5000, trimmed.rangeOfCharacter(from: .letters) != nil else { return }

        processPolledText(trimmed, element: element)
    }

    private func selectionBounds(element: AXUIElement) -> NSRect {
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        guard rangeResult == .success, let rangeVal = selectedRange else {
            return mouseBounds()
        }

        guard CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            return mouseBounds()
        }

        var rangeValue = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeVal as! AXValue, .cfRange, &rangeValue)

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal as! AXValue,
            &boundsValue
        )

        guard boundsResult == .success,
              let boundVal = boundsValue,
              CFGetTypeID(boundVal) == AXValueGetTypeID() else {
            return mouseBounds()
        }

        var rect = CGRect.zero
        if AXValueGetValue(boundVal as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 {
            return rect
        }

        return mouseBounds()
    }

    private func mouseBounds() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        return NSRect(x: mouseLocation.x - 50, y: mouseLocation.y - 10, width: 100, height: 20)
    }

    private func isAccessibilityEnabled() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<TextMonitor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.handleAXNotification(element: element, notification: notification)
    }
}
