import Foundation
import CoreGraphics
import VoiceSessions

struct InputShortcut {
    let name: String
    let helperKey: String
    let shortcut: SystemShortcut
    static let choices: [InputShortcut] = [
        .init(name: "Fn", helperKey: "Fn", shortcut: .init(modifiers: [.init(keyCode: 0x3F, flag: .maskSecondaryFn)], key: nil)!),
        .init(name: "左 Control", helperKey: "LeftControl", shortcut: .init(modifiers: [.leftControl], key: nil)!),
        .init(name: "右 Control", helperKey: "RightControl", shortcut: .init(modifiers: [.rightControl], key: nil)!),
        .init(name: "左 Option", helperKey: "LeftOption", shortcut: .init(modifiers: [.leftOption], key: nil)!),
        .init(name: "右 Option", helperKey: "RightOption", shortcut: .init(modifiers: [.init(keyCode: 0x3D, flag: .maskAlternate)], key: nil)!),
        .init(name: "F8", helperKey: "F8", shortcut: .init(modifiers: [], key: 0x64)!),
        .init(name: "F9", helperKey: "F9", shortcut: .init(modifiers: [], key: 0x65)!),
        .init(name: "F10", helperKey: "F10", shortcut: .init(modifiers: [], key: 0x6D)!)
    ]
}
