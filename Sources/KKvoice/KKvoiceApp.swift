import AppKit
import SwiftUI

@main
struct KKvoiceMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = KKvoiceAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class KKvoiceAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var window: NSWindow!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(
            withTitle: "退出 KKvoice",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        root.submenu = menu
        let appMenu = NSMenu()
        appMenu.addItem(root)
        NSApplication.shared.mainMenu = appMenu

        installMenuBarItem()

        let hostingController = NSHostingController(rootView: MainView(model: model))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 960, height: 680))
        window.minSize = NSSize(width: 860, height: 600)
        window.title = "KKvoice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        window.makeKeyAndOrderFront(nil)
        model.applyAppearance()
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.connect()
    }

    static func makeMenuBarTemplateImage() -> NSImage {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("KKvoice-logo.png")
        let repoFallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Native/Assets/KKvoice-logo.png")
        let source = bundled.flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(contentsOf: repoFallback)
            ?? NSImage(size: NSSize(width: 18, height: 18))

        let canvasSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let srcSize = source.size
            let scale = (srcSize.width > 0 && srcSize.height > 0)
                ? min(rect.width / srcSize.width, rect.height / srcSize.height)
                : 1.0
            let drawW = srcSize.width * scale
            let drawH = srcSize.height * scale
            let drawRect = NSRect(
                x: rect.midX - drawW / 2,
                y: rect.midY - drawH / 2,
                width: drawW,
                height: drawH
            )
            source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSColor.black.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = Self.makeMenuBarTemplateImage()
        item.button?.image = image
        item.button?.toolTip = "KKvoice"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            showMainWindow()
            return
        }
        let menu = NSMenu()
        let show = NSMenuItem(title: "打开 KKvoice", action: #selector(showMainWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 KKvoice",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
