import AppKit
import CoreAudio
import RemoteAudio
import VoiceSessions
import SnapNote
import ServiceManagement

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

@MainActor final class KKvoiceAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let bridge = RemoteBridge()
    private let snapTokenStore = SnapNoteTokenStore()
    private var snapAdapter: SnapNoteHelperActionAdapter?
    private var snapTask: Task<Void, Never>?
    private let snapShortcutKey = "snapNoteNewShortcut"
    private let mappingStore = ButtonMappingStore()
    private lazy var buttonDispatcher = ButtonActionDispatcher(
        mappings: mappingStore.load(),
        send: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 21) }
            try self.bridge.send(message)
        },
        cancelVoice: { [weak self] in self?.voice.cancelWithoutSubmitting() },
        status: { [weak self] text in self?.status.stringValue = text }
    )
    private let output = KKCoreAudioOutput()
    private lazy var audio = RemoteAudioBridge(output: output)
    private var outputSessions: [UUID: UUID] = [:]
    private var inputAppWatchdog: Timer?
    private var inputAppObservedActive = false
    private var inputAppInactiveSamples = 0
    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var mappingsWindow: ButtonMappingsWindowController?
    private let status = NSTextField(labelWithString: "尚未连接")
    private let keyboardStatusLabel = NSTextField(labelWithString: "键盘监听：未连接")
    private let keyboardSettings = KeyboardSettings()
    private var keyboardStatus = KeyboardListenerStatus()
    private let devices = NSPopUpButton()
    private let wakeKey = NSPopUpButton()
    private let inputKey = NSPopUpButton()
    private let voiceMode = NSPopUpButton()
    private var availableDevices: [KKAudioOutputDevice] = []
    private var selectedDeviceUID: String?
    private var chosenInputShortcut = ShortcutDefinition(keyName: "LeftControl")!.systemShortcut
    private var connectButton: NSButton!
    private var disconnectButton: NSButton!
    private var refreshButton: NSButton!
    private let loginItemCheckbox = NSButton(checkboxWithTitle: "开机启动", target: nil, action: nil)
    private lazy var voice: VoiceCoordinator = VoiceCoordinator(
        beginOutput: { [weak self] session in
            guard let self, let uid = self.selectedDeviceUID else {
                throw NSError(domain: "KKvoice", code: 10, userInfo: [NSLocalizedDescriptionKey: "请选择已安装的虚拟音频设备。"])
            }
            let audioID = try self.audio.start(deviceUID: uid)
            self.outputSessions[session] = audioID
        },
        endOutput: { [weak self] session in
            guard let self, let id = self.outputSessions.removeValue(forKey: session) else { return nil }
            _ = self.audio.stop(session: id)
            return self.output.lastStopError
        },
        command: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 11) }
            try self.bridge.send(message)
        },
        shortcut: { [weak self] in
            guard let self else { throw NSError(domain: "KKvoice", code: 12) }
            try SystemShortcutSender.send(self.chosenInputShortcut)
        },
        report: { [weak self] text in self?.status.stringValue = text }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = NSMenuItem(); let menu = NSMenu()
        menu.addItem(withTitle: "退出 KKvoice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = menu; let appMenu = NSMenu(); appMenu.addItem(root)
        NSApplication.shared.mainMenu = appMenu
        installMenuBarItem()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "KKvoice"; window.center()
        let title = NSTextField(labelWithString: "KKvoice"); title.font = .boldSystemFont(ofSize: 22)
        let intro = NSTextField(wrappingLabelWithString: "连接 Chromecast 遥控器，使用所选输入软件的语音快捷键。")
        wakeKey.addItems(withTitles: ["不启用"] + InputShortcut.choices.map(\.name) + ["自定义快捷键…"])
        inputKey.addItems(withTitles: InputShortcut.choices.map(\.name) + ["自定义快捷键…"])
        voiceMode.addItems(withTitles: ["按一次开始，再按一次结束", "短按切换，长按松开结束"])
        voiceMode.selectItem(at: UserDefaults.standard.bool(forKey: "remoteHybridGesture") ? 1 : 0)
        voiceMode.target = self; voiceMode.action = #selector(voiceModeChanged)
        wakeKey.selectItem(at: keyboardSettings.wakeSelection(choices: InputShortcut.choices))
        inputKey.selectItem(at: keyboardSettings.inputSelection(choices: InputShortcut.choices))
        wakeKey.target = self; wakeKey.action = #selector(wakeKeyChanged)
        inputKey.target = self; inputKey.action = #selector(inputKeyChanged)
        refreshButton = NSButton(title: "刷新设备", target: self, action: #selector(refreshDevices))
        let deviceRow = NSStackView(views: [devices, refreshButton]); deviceRow.orientation = .horizontal; deviceRow.spacing = 8
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "虚拟麦克风"), deviceRow],
            [NSTextField(labelWithString: "电脑唤醒键"), wakeKey],
            [NSTextField(labelWithString: "输入软件快捷键"), inputKey],
            [NSTextField(labelWithString: "遥控器语音键"), voiceMode]
        ])
        grid.rowSpacing = 12; grid.columnSpacing = 12
        connectButton = NSButton(title: "连接遥控器", target: self, action: #selector(connect))
        disconnectButton = NSButton(title: "断开连接", target: self, action: #selector(disconnect))
        disconnectButton.isEnabled = false
        let settingsButton = NSButton(title: "按键设置", target: self, action: #selector(openMappings))
        let snapSettingsButton = NSButton(title: "闪念设置", target: self, action: #selector(configureSnapNote))
        let thanksButton = NSButton(title: "鸣谢", target: self, action: #selector(showAcknowledgements))
        let buttons = NSStackView(views: [connectButton, disconnectButton, settingsButton, snapSettingsButton, thanksButton]); buttons.orientation = .horizontal; buttons.spacing = 12
        let note = NSTextField(wrappingLabelWithString: "测试版：请在输入软件中选择相同的虚拟麦克风和快捷键。录音按一次开始、再按一次结束。")
        note.textColor = .secondaryLabelColor
        loginItemCheckbox.target = self; loginItemCheckbox.action = #selector(loginItemChanged)
        if #available(macOS 13.0, *) {
            loginItemCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginItemCheckbox.isEnabled = false
            loginItemCheckbox.toolTip = "开机启动需要 macOS 13 或更高版本。"
        }
        let stack = NSStackView(views: [title, intro, grid, status, keyboardStatusLabel, buttons, loginItemCheckbox, note])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
            ])
        }
        bridge.onStatus = { [weak self] text in self?.status.stringValue = text }
        bridge.onMessage = { [weak self] message in self?.handleHelperMessage(message) }
        buttonDispatcher.createSnapNote = { [weak self] in self?.createSnapNote() }
        refreshDevices()
        updateCustomShortcutTitles()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        connect()
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let imageURL = Bundle.main.resourceURL!.appendingPathComponent("KKvoice-logo.png")
        let source = NSImage(contentsOf: imageURL) ?? NSImage(size: NSSize(width: 18, height: 18))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            source.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
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
        show.target = self; menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 KKvoice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func loginItemChanged() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if loginItemCheckbox.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            let current = SMAppService.mainApp.status
            loginItemCheckbox.state = current == .enabled ? .on : .off
            if current == .requiresApproval { status.stringValue = "请在系统设置的登录项中允许 KKvoice 开机启动。" }
        } catch {
            loginItemCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            status.stringValue = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    @objc private func wakeKeyChanged() {
        if wakeKey.indexOfSelectedItem == InputShortcut.choices.count + 1 {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.wakeDefinition(), globalWake: true) {
                keyboardSettings.saveWakeDefinition(value)
            }
        } else { keyboardSettings.saveWake(selection: wakeKey.indexOfSelectedItem, choices: InputShortcut.choices) }
        wakeKey.selectItem(at: keyboardSettings.wakeSelection(choices: InputShortcut.choices))
        updateCustomShortcutTitles()
    }
    @objc private func voiceModeChanged() {
        UserDefaults.standard.set(voiceMode.indexOfSelectedItem == 1, forKey: "remoteHybridGesture")
    }
    @objc private func inputKeyChanged() {
        if inputKey.indexOfSelectedItem == InputShortcut.choices.count {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.inputDefinition(), globalWake: false) {
                keyboardSettings.saveInputDefinition(value)
            }
        } else { keyboardSettings.saveInput(selection: inputKey.indexOfSelectedItem, choices: InputShortcut.choices) }
        inputKey.selectItem(at: keyboardSettings.inputSelection(choices: InputShortcut.choices))
        updateCustomShortcutTitles()
    }
    private func updateCustomShortcutTitles() {
        let choices = InputShortcut.choices
        if keyboardSettings.wakeSelection(choices: choices) == choices.count + 1,
           let definition = keyboardSettings.wakeDefinition() {
            wakeKey.lastItem?.title = "自定义：\(definition.encoded)"
        } else { wakeKey.lastItem?.title = "自定义快捷键…" }
        if keyboardSettings.inputSelection(choices: choices) == choices.count {
            inputKey.lastItem?.title = "自定义：\(keyboardSettings.inputDefinition().encoded)"
        } else { inputKey.lastItem?.title = "自定义快捷键…" }
    }

    @objc private func refreshDevices() {
        do {
            // Restrict UI to known loopback devices, never speakers or the Mac mic.
            availableDevices = try KKAudioOutputDevices.list().filter {
                $0.uid == "KKvoiceMi2ch_UID" || $0.uid == "vRemoteDr2ch_UID" || $0.name.localizedCaseInsensitiveContains("BlackHole")
            }
            devices.removeAllItems()
            devices.addItems(withTitles: availableDevices.map { "\($0.name.trimmingCharacters(in: .whitespacesAndNewlines)) (\($0.uid))" })
            if let index = availableDevices.firstIndex(where: { $0.uid == "KKvoiceMi2ch_UID" }) {
                devices.selectItem(at: index)
            } else if let index = availableDevices.firstIndex(where: { $0.uid == "vRemoteDr2ch_UID" }) {
                devices.selectItem(at: index)
            }
            devices.isEnabled = !availableDevices.isEmpty
            if availableDevices.isEmpty { devices.addItem(withTitle: "未找到虚拟音频设备") }
        } catch {
            availableDevices = []; devices.removeAllItems(); devices.addItem(withTitle: "无法读取音频设备")
            devices.isEnabled = false; status.stringValue = "读取音频设备失败：\(error)"
        }
    }

    @objc private func showAcknowledgements() {
        let alert = NSAlert()
        alert.messageText = "鸣谢开源项目"
        alert.informativeText = "BlackHole\n虚拟音频驱动基础\n\nvRemoter\n遥控器与音频驱动实现参考"
        alert.addButton(withTitle: "BlackHole GitHub")
        alert.addButton(withTitle: "vRemoter GitHub")
        alert.addButton(withTitle: "关闭")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://github.com/ExistentialAudio/BlackHole")!)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://github.com/VincentKingHsu/vRemoter")!)
        default: break
        }
    }

    @objc private func connect() {
        guard connectButton.isEnabled else { return }
        guard let resourceURL = Bundle.main.resourceURL else { status.stringValue = "找不到应用资源。"; return }
        let index = devices.indexOfSelectedItem
        selectedDeviceUID = availableDevices.indices.contains(index) ? availableDevices[index].uid : nil
        chosenInputShortcut = keyboardSettings.inputDefinition().systemShortcut
        let wakeDefinition = keyboardSettings.wakeDefinition()
        guard voice.setRemoteGesture(voiceMode.indexOfSelectedItem == 1 ? .hybrid : .toggle) else {
            status.stringValue = "请先结束当前收音。"; return
        }
        // Start the remote audio route before Vokie receives its toggle. Passing
        // through the physical key can make Vokie open the input before CoreAudio
        // has attached to the virtual microphone, which yields an empty recording.
        let passThrough = false
        guard voice.setKeyboardPassThrough(passThrough) else { status.stringValue = "请先结束当前收音。"; return }
        let selectedWake = wakeDefinition?.keyName
        let helper = resourceURL.appendingPathComponent("KKvoiceRemoteHelper.app/Contents/MacOS/KKvoiceRemoteHelper")
        do {
            keyboardStatus.connecting(key: selectedWake)
            keyboardStatusLabel.stringValue = keyboardStatus.text
            try bridge.start(helperURL: helper, keyboardKey: selectedWake, keyboardModifiers: wakeDefinition?.modifiers ?? [], keyboardPassThrough: passThrough)
            snapAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported: true) { [weak self] message in
                DispatchQueue.main.async { [weak self] in
                    do { try self?.bridge.send(message.wireFields) }
                    catch { Task { await self?.snapAdapter?.helperDisconnected() } }
                }
            }
            connectButton.isEnabled = false; disconnectButton.isEnabled = true
            devices.isEnabled = false; wakeKey.isEnabled = false; inputKey.isEnabled = false; voiceMode.isEnabled = false; refreshButton.isEnabled = false
        } catch {
            keyboardStatus.receive(["type": "helper_process_exited"])
            keyboardStatusLabel.stringValue = keyboardStatus.text
            bridge.stop(); status.stringValue = error.localizedDescription
        }
    }

    @objc private func disconnect() {
        stopInputAppWatchdog()
        snapTask?.cancel()
        if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
        snapAdapter = nil
        voice.setReady(false); bridge.stop()
    }
    @objc private func configureSnapNote() {
        guard connectButton.isEnabled else { status.stringValue = "请先断开遥控器，再修改闪念设置。"; return }
        let alert = NSAlert()
        alert.messageText = "闪念笔记设置"
        alert.informativeText = "输入本机接口 Token；留空表示保留已有 Token。"
        alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Token"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if !field.stringValue.isEmpty { try snapTokenStore.save(field.stringValue) }
            let previous = UserDefaults.standard.string(forKey: snapShortcutKey).flatMap(ShortcutDefinition.init(encoded:))
            guard let selected = ShortcutPicker.prompt(previous: previous, globalWake: false),
                  SnapNoteCoordinator.validShortcut(selected.encoded) else {
                status.stringValue = "请设置带修饰键的闪念新建快捷键。"; return
            }
            UserDefaults.standard.set(selected.encoded, forKey: snapShortcutKey)
            status.stringValue = "闪念快捷键已保存；请确认与闪念笔记设置一致。"
        } catch { status.stringValue = "无法保存闪念令牌：\(error.localizedDescription)" }
    }
    private func createSnapNote() {
        guard snapTask == nil else { status.stringValue = "闪念笔记操作进行中。"; return }
        guard let adapter = snapAdapter else { status.stringValue = "请先连接遥控器。"; return }
        guard case .idle = voice.phase else { status.stringValue = "请先结束语音输入。"; return }
        guard let shortcut = UserDefaults.standard.string(forKey: snapShortcutKey) else { status.stringValue = "请先配置闪念笔记快捷键。"; return }
        do {
            guard let token = try snapTokenStore.load() else { status.stringValue = "请先配置闪念笔记 Token。"; return }
            let client = try SnapNoteMCPClient(token: token)
            let coordinator = SnapNoteCoordinator(client: client, native: adapter, isRecording: { [weak self] in
                await self?.isVoiceActive() ?? true
            })
            status.stringValue = "正在新建闪念笔记…"
            snapTask = Task { @MainActor [weak self] in
                let result = await coordinator.createAndTag(shortcut: shortcut)
                guard let self else { return }
                self.snapTask = nil
                if result.succeeded { self.status.stringValue = "闪念笔记已创建并添加标签。" }
                else if result.noteMayExist { self.status.stringValue = "闪念操作未完成，笔记可能已创建，请检查后再试。" }
                else { self.status.stringValue = "闪念操作未完成：\(String(describing: result.error))" }
            }
        } catch { status.stringValue = "闪念笔记配置不可用。" }
    }
    private func isVoiceActive() -> Bool {
        if case .idle = voice.phase { return false }
        return true
    }
    @objc private func openMappings() {
        let controller = ButtonMappingsWindowController(store: mappingStore, mappings: buttonDispatcher.mappings, canCaptureShortcut: { [weak self] in self?.connectButton.isEnabled == true }) { [weak self] mappings in
            self?.buttonDispatcher.mappings = mappings
        }
        mappingsWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    private func handleHelperMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String, let raw = message["actionId"] as? String,
           let id = UUID(uuidString: raw), let adapter = snapAdapter {
            let prevented = message["prevented"] as? Bool
            Task { await adapter.handleHelperEvent(type: type, actionID: id, prevented: prevented) }
        }
        keyboardStatus.receive(message)
        keyboardStatusLabel.stringValue = keyboardStatus.text
        switch message["type"] as? String {
        case "device_ready": voice.setReady(true); status.stringValue = "遥控器语音通道已连接"
        case "hid_connected": status.stringValue = "已检测到遥控器按键"
        case "scanning": status.stringValue = "正在查找遥控器…"
        case "ble_disconnected", "bluetooth_off": voice.setReady(false); status.stringValue = "遥控器蓝牙已断开"
        case "hid_disconnected": buttonDispatcher.deviceDisconnected(); status.stringValue = "遥控器按键已断开"
        case "button_down":
            if let id = message["buttonId"] as? String { buttonDispatcher.down(id.uppercased()) }
        case "button_up":
            if let id = message["buttonId"] as? String { buttonDispatcher.up(id.uppercased()) }
        case "app_switcher_state": buttonDispatcher.switcherActive = message["active"] as? Bool == true
        case "action_error": status.stringValue = message["message"] as? String ?? "按键动作失败。"
        case "voice_press":
            guard snapTask == nil else { status.stringValue = "闪念操作进行中，请稍候再录音。"; return }
            voice.press(.remote)
        case "voice_release": voice.release(.remote)
        case "keyboard_trigger_down":
            guard snapTask == nil else { status.stringValue = "闪念操作进行中，请稍候再录音。"; return }
            voice.press(.keyboard)
        case "keyboard_trigger_up":
            if message["interrupted"] as? Bool == true { voice.keyboardInterrupted() }
            else { voice.release(.keyboard) }
        case "keyboard_cancel_session": voice.cancelWithoutSubmitting()
        case "capture_probe_started": status.stringValue = "正在确认遥控器语音请求…"
        case "capture_probe_timeout": status.stringValue = "未建立语音会话，已停止遥控器收音。"
        case "audio_start": voice.audioStarted()
        case "audio_reopen_requested":
            status.stringValue = "正在恢复遥控器收音…"
        case "audio_stream_progress":
            if case .recording = voice.phase, let frames = message["frames"] as? Int {
                status.stringValue = "遥控器收音中，已接收 \(frames) 帧。"
                startInputAppWatchdog()
            }
        case "audio_frame":
            guard message["sampleRate"] as? Int == 16_000,
                  let encoded = message["pcmBase64"] as? String,
                  let pcm = Data(base64Encoded: encoded),
                  let session = outputSessions.values.first else { return }
            _ = audio.receive(pcm, session: session)
        case "mic_open_error":
            if let code = message["code"] as? NSNumber {
                voice.audioFailed("遥控器麦克风未能开启（错误码 \(code.uint64Value)）。")
            } else { voice.audioFailed("遥控器麦克风未能开启。") }
        case "permission_required":
            voice.setReady(false)
            switch message["permission"] as? String {
            case "accessibility": status.stringValue = "请在系统设置中允许 KKvoice Remote Helper 使用辅助功能。"
            case "input-monitoring": status.stringValue = "请在系统设置中允许 KKvoice Remote Helper 进行输入监控。"
            case "bluetooth": status.stringValue = "请在系统设置中允许 KKvoice Remote Helper 使用蓝牙。"
            default: status.stringValue = "请检查系统权限设置。"
            }
        case "device_error", "device_not_found": voice.setReady(false); status.stringValue = message["message"] as? String ?? "遥控器暂不可用"
        case "helper_process_exited":
            stopInputAppWatchdog()
            snapTask?.cancel()
            if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
            snapAdapter = nil
            buttonDispatcher.reset()
            voice.setReady(false)
            connectButton.isEnabled = true; disconnectButton.isEnabled = false
            wakeKey.isEnabled = true; inputKey.isEnabled = true; voiceMode.isEnabled = true; refreshButton.isEnabled = true
            devices.isEnabled = !availableDevices.isEmpty
        default: break
        }
    }
    private func startInputAppWatchdog() {
        guard inputAppWatchdog == nil else { return }
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
        inputAppWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
            guard let self else { timer.invalidate(); return }
            guard case .recording = self.voice.phase else { self.stopInputAppWatchdog(); return }
            guard let uid = self.selectedDeviceUID else { return }
            guard let active = InputApplicationAudioMonitor.isVokieCapturing(deviceUID: uid) else {
                self.inputAppInactiveSamples = 0
                return
            }
            if active {
                self.inputAppObservedActive = true
                self.inputAppInactiveSamples = 0
                return
            }
            if self.inputAppObservedActive {
                self.inputAppInactiveSamples += 1
                guard self.inputAppInactiveSamples >= 3 else { return }
                self.voice.cancelWithoutSubmitting()
                self.stopInputAppWatchdog()
                self.status.stringValue = "Vokie 已结束或取消录音，遥控器收音已关闭。"
            }
            }
        }
    }
    private func stopInputAppWatchdog() {
        inputAppWatchdog?.invalidate(); inputAppWatchdog = nil
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
    }
    func applicationWillTerminate(_ notification: Notification) { disconnect() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
