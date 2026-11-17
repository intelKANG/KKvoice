import Foundation
import CoreGraphics

/// A validated, persistable shortcut using physical macOS key codes. Letters
/// refer to physical ANSI positions, not characters in the current layout.
/// Existing plugin values (`key:A`, `shortcut:command+shift:K`, and
/// `shortcut:none:LeftControl`) are accepted; named left/right modifiers extend
/// that format for KKvoice. Generic modifiers resolve to their left side.
public struct ShortcutDefinition: Equatable, Codable {
    public let keyName: String
    public let modifiers: [String]

    public static let supportedKeyNames: [String] = {
        (1...12).map { "F\($0)" } + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init) +
        ["Space", "Return", "Escape", "Tab", "Backspace", "ForwardDelete", "Home", "End", "PageUp", "PageDown", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "LeftCommand", "RightCommand", "LeftOption", "RightOption", "LeftControl", "RightControl", "LeftShift", "RightShift", "Fn"]
    }()

    private static let keyCodes: [String: CGKeyCode] = [
        "F1":0x7A,"F2":0x78,"F3":0x63,"F4":0x76,"F5":0x60,"F6":0x61,
        "F7":0x62,"F8":0x64,"F9":0x65,"F10":0x6D,"F11":0x67,"F12":0x6F,
        "A":0x00,"B":0x0B,"C":0x08,"D":0x02,"E":0x0E,"F":0x03,"G":0x05,"H":0x04,
        "I":0x22,"J":0x26,"K":0x28,"L":0x25,"M":0x2E,"N":0x2D,"O":0x1F,
        "P":0x23,"Q":0x0C,"R":0x0F,"S":0x01,"T":0x11,"U":0x20,"V":0x09,
        "W":0x0D,"X":0x07,"Y":0x10,"Z":0x06,
        "0":0x1D,"1":0x12,"2":0x13,"3":0x14,"4":0x15,"5":0x17,"6":0x16,"7":0x1A,"8":0x1C,"9":0x19,
        "Space":0x31,"Return":0x24,"Escape":0x35,"Tab":0x30,"Backspace":0x33,"ForwardDelete":0x75,
        "Home":0x73,"End":0x77,"PageUp":0x74,"PageDown":0x79,"ArrowUp":0x7E,"ArrowDown":0x7D,"ArrowLeft":0x7B,"ArrowRight":0x7C,
        "LeftCommand":0x37,"RightCommand":0x36,"LeftOption":0x3A,"RightOption":0x3D,
        "LeftControl":0x3B,"RightControl":0x3E,"LeftShift":0x38,"RightShift":0x3C,"Fn":0x3F
    ]
    private struct ModifierSpec {
        let canonical: String
        let code: CGKeyCode
        let flag: CGEventFlags
    }
    private static let genericModifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

    private static let modifierSpecs: [String: ModifierSpec] = [
        "command":.init(canonical:"command",code:0x37,flag:CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008)),
        "leftcommand":.init(canonical:"leftCommand",code:0x37,flag:CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008)),
        "rightcommand":.init(canonical:"rightCommand",code:0x36,flag:CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0010)),
        "option":.init(canonical:"option",code:0x3A,flag:CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0020)),
        "leftoption":.init(canonical:"leftOption",code:0x3A,flag:CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0020)),
        "rightoption":.init(canonical:"rightOption",code:0x3D,flag:CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040)),
        "control":.init(canonical:"control",code:0x3B,flag:CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x0001)),
        "leftcontrol":.init(canonical:"leftControl",code:0x3B,flag:CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x0001)),
        "rightcontrol":.init(canonical:"rightControl",code:0x3E,flag:CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2000)),
        "shift":.init(canonical:"shift",code:0x38,flag:CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0002)),
        "leftshift":.init(canonical:"leftShift",code:0x38,flag:CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0002)),
        "rightshift":.init(canonical:"rightShift",code:0x3C,flag:CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0004)),
        "fn":.init(canonical:"fn",code:0x3F,flag:.maskSecondaryFn)
    ]
    private static let modifierKeys: Set<String> = ["LeftCommand","RightCommand","LeftOption","RightOption","LeftControl","RightControl","LeftShift","RightShift","Fn"]

    public init?(keyName: String, modifiers: [String] = []) {
        guard let canonicalKey = Self.supportedKeyNames.first(where: { $0.caseInsensitiveCompare(keyName) == .orderedSame }),
              Self.keyCodes[canonicalKey] != nil else { return nil }
        var specs: [ModifierSpec] = []
        for name in modifiers {
            guard let spec = Self.modifierSpecs[name.lowercased()],
                  !specs.contains(where: { ($0.flag.rawValue & Self.genericModifierMask) == (spec.flag.rawValue & Self.genericModifierMask) }) else { return nil }
            specs.append(spec)
        }
        // A standalone modifier is supported, but not a modifier plus another
        // modifier as a main key: the upstream config has the same constraint.
        guard !(Self.modifierKeys.contains(canonicalKey) && !specs.isEmpty) else { return nil }
        self.keyName = canonicalKey
        self.modifiers = specs.map(\.canonical)
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 && parts[0] == "key" && parts[1].count == 1,
           parts[1].range(of: "^[A-Za-z0-9]$", options: .regularExpression) != nil {
            self.init(keyName: parts[1]); return
        }
        guard parts.count == 3, parts[0] == "shortcut", !parts[1].isEmpty else { return nil }
        let mods = parts[1] == "none" ? [] : parts[1].split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        self.init(keyName: parts[2], modifiers: mods)
    }

    public var encoded: String { "shortcut:\(modifiers.isEmpty ? "none" : modifiers.joined(separator: "+")):\(keyName)" }

    /// Ordinary letters/numbers should never be grabbed globally unmodified.
    public var suitableForGlobalTrigger: Bool {
        !(modifiers.isEmpty && keyName.count == 1 && keyName.range(of: "^[A-Z0-9]$", options: .regularExpression) != nil)
    }

    /// Original helper understands only aggregate modifier names. Preserve the
    /// handedness of the main key, but never silently downgrade a sided chord.
    /// Use SystemShortcutSender for combinations containing sided modifiers.
    public var legacyHelperEncoding: String? {
        let generic = Set(["command", "option", "control", "shift", "fn"])
        guard modifiers.allSatisfy({ generic.contains($0) }) else { return nil }
        return encoded
    }

    /// Existing helper's keyboardTrigger accepts fewer main keys than remote
    /// action mappings. Non-generic chord modifiers require helper changes.
    public var supportedByLegacyKeyboardTrigger: Bool {
        let allowed = (1...12).map { "F\($0)" } + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)
            + ["Space", "Return", "Escape", "Tab"] + Array(Self.modifierKeys)
        return suitableForGlobalTrigger && allowed.contains(keyName) && legacyHelperEncoding != nil
    }

    public var systemShortcut: SystemShortcut {
        if Self.modifierKeys.contains(keyName) {
            let spec = Self.modifierSpecs[keyName.lowercased()]!
            return SystemShortcut(modifiers: [.init(keyCode: spec.code, flag: spec.flag)], key: nil)!
        }
        let resolved = modifiers.map { name -> SystemShortcut.Modifier in
            let spec = Self.modifierSpecs[name.lowercased()]!
            return .init(keyCode: spec.code, flag: spec.flag)
        }
        return SystemShortcut(modifiers: resolved, key: Self.keyCodes[keyName]!)!
    }

    private enum CodingKeys: String, CodingKey { case keyName, modifiers }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .keyName)
        let mods = try container.decode([String].self, forKey: .modifiers)
        guard let valid = Self(keyName: key, modifiers: mods) else {
            throw DecodingError.dataCorruptedError(forKey: .keyName, in: container, debugDescription: "Invalid shortcut")
        }
        self = valid
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyName, forKey: .keyName)
        try container.encode(modifiers, forKey: .modifiers)
    }
}
