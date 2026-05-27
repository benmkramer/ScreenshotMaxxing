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

    static let defaultAreaCapture = GlobalKeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_5),
        carbonModifiers: UInt32(controlKey | shiftKey)
    )
    static let commandShiftAreaCapture = GlobalKeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
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

enum HotKeyManagerError: LocalizedError, Equatable {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerRegistrationFailed(let status):
            "Could not install the global shortcut handler. OSStatus \(status)."
        case .hotKeyRegistrationFailed(let status):
            "Could not register the global shortcut. OSStatus \(status)."
        }
    }
}

final class HotKeyManager {
    static let areaCaptureHotKeyID: UInt32 = 1
    static let commandShiftAreaCaptureHotKeyID: UInt32 = 2
    private static let hotKeySignature = OSType(0x534D6178) // SMax

    private let actionHandler: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    private(set) var registeredShortcut: GlobalKeyboardShortcut?
    private(set) var registeredCommandShiftAreaShortcut: GlobalKeyboardShortcut?

    init(actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
    }

    deinit {
        invalidate()
    }

    func registerAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut = .defaultAreaCapture) throws {
        unregisterHotKey(id: Self.areaCaptureHotKeyID)
        try installEventHandlerIfNeeded()
        try registerHotKey(shortcut, id: Self.areaCaptureHotKeyID)

        registeredShortcut = shortcut
    }

    func registerCommandShiftAreaCaptureShortcut() throws {
        unregisterHotKey(id: Self.commandShiftAreaCaptureHotKeyID)

        guard registeredShortcut != .commandShiftAreaCapture else {
            registeredCommandShiftAreaShortcut = nil
            return
        }

        try installEventHandlerIfNeeded()
        try registerHotKey(.commandShiftAreaCapture, id: Self.commandShiftAreaCaptureHotKeyID)

        registeredCommandShiftAreaShortcut = .commandShiftAreaCapture
    }

    func unregisterAreaCaptureShortcut() {
        unregisterHotKey(id: Self.areaCaptureHotKeyID)
        unregisterHotKey(id: Self.commandShiftAreaCaptureHotKeyID)
        registeredShortcut = nil
        registeredCommandShiftAreaShortcut = nil
    }

    func invalidate() {
        unregisterAreaCaptureShortcut()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotKeyPressed(id: UInt32) {
        guard id == Self.areaCaptureHotKeyID || id == Self.commandShiftAreaCaptureHotKeyID else {
            return
        }

        actionHandler()
    }

    private func registerHotKey(_ shortcut: GlobalKeyboardShortcut, id: UInt32) throws {
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: id
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
            throw HotKeyManagerError.hotKeyRegistrationFailed(status)
        }

        hotKeyRefs[id] = newHotKeyRef
    }

    private func unregisterHotKey(id: UInt32) {
        if let hotKeyRef = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(hotKeyRef)
        }

        if id == Self.areaCaptureHotKeyID {
            registeredShortcut = nil
        } else if id == Self.commandShiftAreaCaptureHotKeyID {
            registeredCommandShiftAreaShortcut = nil
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
