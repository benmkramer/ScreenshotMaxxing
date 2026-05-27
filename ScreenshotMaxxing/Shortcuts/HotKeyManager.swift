//
//  HotKeyManager.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import Carbon

struct GlobalKeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    nonisolated static let defaultAreaCapture = GlobalKeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(controlKey | shiftKey)
    )

    nonisolated static let defaultCaptureOptions = GlobalKeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_5),
        carbonModifiers: UInt32(controlKey | shiftKey)
    )

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    nonisolated static func == (lhs: GlobalKeyboardShortcut, rhs: GlobalKeyboardShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.carbonModifiers == rhs.carbonModifiers
    }

    init?(event: NSEvent) {
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)

        guard Self.hasActionModifier(carbonModifiers) else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers)
    }

    var displayString: String {
        var parts: [String] = []

        if carbonModifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }

        if carbonModifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }

        if carbonModifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }

        if carbonModifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }

        parts.append(Self.keyDisplayName(for: keyCode))

        return parts.joined(separator: "-")
    }

    var isReservedSystemScreenshotShortcut: Bool {
        let keyCode = Int(keyCode)
        let usesCommandShift = carbonModifiers & UInt32(cmdKey | shiftKey) == UInt32(cmdKey | shiftKey)

        return usesCommandShift && [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(keyCode)
    }

    static func keyDisplayName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_Space: "Space"
        case kVK_Escape: "Esc"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Delete: "Delete"
        default: "Key \(keyCode)"
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0

        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }

        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        return carbonModifiers
    }

    private static func hasActionModifier(_ carbonModifiers: UInt32) -> Bool {
        carbonModifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }
}

enum HotKeyAction: UInt32, Equatable {
    case captureArea = 1
    case showCaptureOptions = 2
}

enum HotKeyManagerError: LocalizedError, Equatable {
    case systemShortcutReserved(GlobalKeyboardShortcut)
    case shortcutAlreadyRegistered(GlobalKeyboardShortcut)
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(GlobalKeyboardShortcut, OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemShortcutReserved(let shortcut):
            "\(shortcut.displayString) is reserved by macOS screenshots. Choose another shortcut, such as Control-Shift-4."
        case .shortcutAlreadyRegistered(let shortcut):
            "\(shortcut.displayString) is already used by another ScreenshotMaxxing shortcut."
        case .eventHandlerRegistrationFailed(let status):
            "Could not install the global shortcut handler. OSStatus \(status)."
        case .hotKeyRegistrationFailed(let shortcut, let status):
            "Could not register \(shortcut.displayString). OSStatus \(status)."
        }
    }
}

final class HotKeyManager {
    static let areaCaptureHotKeyID = HotKeyAction.captureArea.rawValue
    static let captureOptionsHotKeyID = HotKeyAction.showCaptureOptions.rawValue
    private static let hotKeySignature = OSType(0x534D6178) // SMax

    private let actionHandler: (HotKeyAction) -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var registeredShortcuts: [HotKeyAction: GlobalKeyboardShortcut] = [:]

    var registeredAreaCaptureShortcut: GlobalKeyboardShortcut? {
        registeredShortcuts[.captureArea]
    }

    var registeredCaptureOptionsShortcut: GlobalKeyboardShortcut? {
        registeredShortcuts[.showCaptureOptions]
    }

    init(actionHandler: @escaping (HotKeyAction) -> Void) {
        self.actionHandler = actionHandler
    }

    deinit {
        invalidate()
    }

    func registerAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut = .defaultAreaCapture) throws {
        try registerShortcut(shortcut, for: .captureArea)
    }

    func registerCaptureOptionsShortcut(_ shortcut: GlobalKeyboardShortcut = .defaultCaptureOptions) throws {
        try registerShortcut(shortcut, for: .showCaptureOptions)
    }

    func unregisterAreaCaptureShortcut() {
        unregisterShortcut(for: .captureArea)
    }

    func unregisterCaptureOptionsShortcut() {
        unregisterShortcut(for: .showCaptureOptions)
    }

    func invalidate() {
        for action in Array(hotKeyRefs.keys) {
            unregisterShortcut(for: action)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotKeyPressed(id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else {
            return
        }

        actionHandler(action)
    }

    private func registerShortcut(_ shortcut: GlobalKeyboardShortcut, for action: HotKeyAction) throws {
        guard !shortcut.isReservedSystemScreenshotShortcut else {
            throw HotKeyManagerError.systemShortcutReserved(shortcut)
        }

        guard !isRegistered(shortcut, excluding: action) else {
            throw HotKeyManagerError.shortcutAlreadyRegistered(shortcut)
        }

        unregisterShortcut(for: action)
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: action.rawValue
        )
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr else {
            throw HotKeyManagerError.hotKeyRegistrationFailed(shortcut, status)
        }

        hotKeyRefs[action] = newHotKeyRef
        registeredShortcuts[action] = shortcut
    }

    private func unregisterShortcut(for action: HotKeyAction) {
        if let hotKeyRef = hotKeyRefs[action] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs[action] = nil
        }

        registeredShortcuts[action] = nil
    }

    private func isRegistered(_ shortcut: GlobalKeyboardShortcut, excluding excludedAction: HotKeyAction) -> Bool {
        registeredShortcuts.contains { action, registeredShortcut in
            action != excludedAction && registeredShortcut == shortcut
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr else {
                    return parameterStatus
                }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handleHotKeyPressed(id: hotKeyID.id)

                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotKeyManagerError.eventHandlerRegistrationFailed(status)
        }
    }
}
