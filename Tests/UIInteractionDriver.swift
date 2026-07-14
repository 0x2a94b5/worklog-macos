import AppKit
import ApplicationServices
import Darwin
import Foundation

enum UIInteractionError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

@main
struct UIInteractionDriver {
    static func main() throws {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("UI interaction test timed out\n".utf8))
            Darwin.exit(2)
        }

        guard CommandLine.arguments.count == 3,
              let processID = Int32(CommandLine.arguments[1]) else {
            throw UIInteractionError.message("Usage: UIInteractionDriver <pid> <task-title>")
        }
        guard AXIsProcessTrusted() else {
            throw UIInteractionError.message("Accessibility permission is required for UI interaction tests")
        }

        let originalTitle = CommandLine.arguments[2]
        let submittedTitle = originalTitle + " Enter"
        let outsideSavedTitle = submittedTitle + " Outside"
        let application = AXUIElementCreateApplication(processID)

        NSRunningApplication(processIdentifier: processID)?.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        waitBriefly()
        let bounds: CGRect = try wait(timeout: 4) { windowBounds(for: processID) }
        let outsidePoint = CGPoint(x: bounds.maxX - 100, y: bounds.maxY - 100)

        log("testing initial focus")
        let taskPoint = try focusTask(
            in: application,
            expectedText: originalTitle
        )
        try verifyFocusedEditor(in: application, expectedText: originalTitle)

        typeText(" Enter")
        pressKey(36)
        waitBriefly()

        doubleClick(taskPoint)
        try verifyFocusedEditor(in: application, expectedText: submittedTitle)
        typeText(" Cancelled")
        pressKey(53)
        waitBriefly()

        doubleClick(taskPoint)
        try verifyFocusedEditor(in: application, expectedText: submittedTitle)
        typeText(" Outside")
        click(outsidePoint, count: 1)
        waitBriefly()

        doubleClick(taskPoint)
        try verifyFocusedEditor(in: application, expectedText: outsideSavedTitle)
        pressKey(53)

        print("UI interaction test passed: focus, caret, Enter, Escape, and outside-click save")
    }

    private static func focusTask(
        in application: AXUIElement,
        expectedText: String
    ) throws -> CGPoint {
        let point: CGPoint = try wait(timeout: 4) {
            elementPoint(matching: expectedText, in: application)
        }
        doubleClick(point)
        try verifyFocusedEditor(in: application, expectedText: expectedText)
        return point
    }

    private static func elementPoint(matching text: String, in root: AXUIElement) -> CGPoint? {
        var visited = Set<CFHashCode>()
        return elementPoint(matching: text, in: root, depth: 0, visited: &visited)
    }

    private static func elementPoint(
        matching text: String,
        in element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>
    ) -> CGPoint? {
        guard depth <= 16, visited.insert(CFHash(element)).inserted else { return nil }

        let candidateTexts = [
            copyStringAttribute(element, kAXValueAttribute),
            copyStringAttribute(element, kAXTitleAttribute),
            copyStringAttribute(element, kAXDescriptionAttribute)
        ]
        if candidateTexts.compactMap({ $0 }).contains(where: { $0 == text || $0.contains(text) }),
           let point = elementCenter(element) {
            return point
        }

        for child in copyElementsAttribute(element, kAXChildrenAttribute) {
            if let point = elementPoint(
                matching: text,
                in: child,
                depth: depth + 1,
                visited: &visited
            ) {
                return point
            }
        }
        return nil
    }

    private static func elementCenter(_ element: AXUIElement) -> CGPoint? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute),
              let sizeValue = copyAttribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private static func focusedEditorMatches(in application: AXUIElement, expectedText: String) -> Bool {
        guard let focused = copyElementAttribute(application, kAXFocusedUIElementAttribute) else { return false }
        return copyStringAttribute(focused, kAXRoleAttribute) == kAXTextFieldRole
            && copyStringAttribute(focused, kAXValueAttribute) == expectedText
    }

    private static func verifyFocusedEditor(in application: AXUIElement, expectedText: String) throws {
        let editor: AXUIElement = try wait(timeout: 3) {
            guard let focused = copyElementAttribute(application, kAXFocusedUIElementAttribute),
                  copyStringAttribute(focused, kAXRoleAttribute) == kAXTextFieldRole,
                  copyStringAttribute(focused, kAXValueAttribute) == expectedText else { return nil }
            return focused
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        guard let rangeValue = copyAttribute(editor, kAXSelectedTextRangeAttribute) else {
            throw UIInteractionError.message("Focused title editor has no selected text range")
        }
        var selectedRange = CFRange()
        let axValue = unsafeBitCast(rangeValue, to: AXValue.self)
        guard AXValueGetValue(axValue, .cfRange, &selectedRange) else {
            throw UIInteractionError.message("Unable to read title caret location")
        }
        let expectedLocation = (expectedText as NSString).length
        guard selectedRange.location == expectedLocation, selectedRange.length == 0 else {
            throw UIInteractionError.message(
                "Expected caret at \(expectedLocation), got \(selectedRange.location),\(selectedRange.length)"
            )
        }
    }

    private static func wait<T>(timeout: TimeInterval, condition: () -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = condition() { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        throw UIInteractionError.message("Timed out waiting for UI state")
    }

    private static func windowBounds(for processID: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        return windows.compactMap { window -> CGRect? in
            guard window[kCGWindowOwnerPID as String] as? Int32 == processID,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: unsafeBitCast(bounds, to: CFDictionary.self))
        }
        .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func doubleClick(_ point: CGPoint) {
        postMouse(point: point, type: .leftMouseDown, clickCount: 1)
        postMouse(point: point, type: .leftMouseUp, clickCount: 1)
        usleep(90_000)
        postMouse(point: point, type: .leftMouseDown, clickCount: 2)
        postMouse(point: point, type: .leftMouseUp, clickCount: 2)
    }

    private static func click(_ point: CGPoint, count: Int64) {
        postMouse(point: point, type: .leftMouseDown, clickCount: count)
        postMouse(point: point, type: .leftMouseUp, clickCount: count)
    }

    private static func waitBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private static func postMouse(point: CGPoint, type: CGEventType, clickCount: Int64) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.post(tap: .cghidEventTap)
    }

    private static func typeText(_ text: String) {
        let characters = Array(text.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        keyDown.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        keyUp.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func pressKey(_ keyCode: CGKeyCode) {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private static func copyElementsAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        copyAttribute(element, attribute) as? [AXUIElement] ?? []
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
