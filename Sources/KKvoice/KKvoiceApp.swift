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

        let hostingController = NSHostingController(rootView: MainView(model: model))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.contentMinSize = NSSize(width: 980, height: 660)
        window.minSize = NSSize(width: 980, height: 660)
        window.title = "KKvoice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        model.onAppearanceChanged = { [weak self] appearance in
            self?.window?.appearance = appearance
            // Keep status item button & status bar window appearance nil so macOS
            // automatically tints the template icon based on the menu bar background.
            self?.statusItem?.button?.appearance = nil
            self?.statusItem?.button?.contentTintColor = nil
            self?.statusItem?.button?.window?.appearance = nil
        }
        model.onMenuBarIconPreferenceChanged = { [weak self] enabled in
            self?.updateMenuBarItem(enabled: enabled)
        }

        updateMenuBarItem(enabled: model.showMenuBarIcon)
        model.applyAppearance()

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if model.checkAndPromptDriverOnLaunch() {
            model.connect()
        }
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

        let ptSize = NSSize(width: 18, height: 18)
        let pxWide = 36
        let pxHigh = 36
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxWide,
            pixelsHigh: pxHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = ptSize
            source.isTemplate = true
            return source
        }
        rep.size = ptSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: ptSize)
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
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: ptSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private func updateMenuBarItem(enabled: Bool) {
        if enabled {
            if statusItem == nil {
                installMenuBarItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
            }
        }
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = Self.makeMenuBarTemplateImage()
        item.button?.image = image
        item.button?.appearance = nil
        item.button?.contentTintColor = nil
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
        window.appearance = model.appearanceMode.nsAppearance
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        guard model.confirmDiscardOrSaveIfNeeded() else { return false }
        sender.orderOut(nil)
        if model.showMenuBarIcon {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
