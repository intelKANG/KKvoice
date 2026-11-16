import AppKit
import Combine
import CoreAudio
import Foundation
import RemoteAudio
import ServiceManagement
import SnapNote
import SwiftUI
import VoiceSessions

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var systemImage: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case connection
    case mappings
    case snapNote
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "连接"
        case .mappings: return "按键"
        case .snapNote: return "闪念笔记"
        case .general: return "通用"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: return "link"
        case .mappings: return "keyboard"
        case .snapNote: return "note.text"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

typealias SidebarPage = SidebarTab

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case keysConnected
    case voiceReady
    case recording
    case error(String)
    case permissionRequired(String)

    var tone: StatusTone {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .keysConnected, .voiceReady:
            return .connected
        case .recording:
            return .recording
        case .permissionRequired:
            return .warning
        case .error:
            return .error
        }
    }

    var badgeTitle: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .keysConnected:
            return "按键已连"
        case .voiceReady:
            return "已连接"
        case .recording:
            return "收音中"
        case .permissionRequired:
            return "需要权限"
        case .error:
            return "连接异常"
        }
    }

    var headlineTitle: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "正在连接…"
        case .keysConnected:
            return "按键已就绪"
        case .voiceReady:
            return "已连接"
        case .recording:
            return "收音中"
        case .permissionRequired:
            return "需要权限"
        case .error:
            return "连接异常"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: SidebarTab = .connection
    @Published var connectionPhase: ConnectionPhase = .disconnected
    @Published var statusText: String = "未连接"
    @Published var keyboardStatusText: String = "未连接"
    @Published var keyboardState: KeyboardListenerStatus.State = .stopped

    @Published var isSessionActive: Bool = false
    @Published var hidConnected: Bool = false
    @Published var voiceChannelReady: Bool = false
    @Published var isRecording: Bool = false
    @Published var recordingFrames: Int = 0
    @Published var requiredPermission: String? = nil
    @Published var lastPressedButtonID: String? = nil

    @Published var availableDevices: [KKAudioOutputDevice] = []
    @Published var selectedDeviceIndex: Int = 0
    @Published var deviceLoadFailed: Bool = false
    @Published var isDriverInstalling: Bool = false
    @Published var driverInstallMessage: String? = nil
    @Published var driverInstallError: String? = nil

    @Published var availableMacMics: [KKAudioInputDevice] = []
    @Published var selectedMacMicUID: String = ""
    @Published var currentAudioSource: AudioSource? = nil

    @Published var wakeSelectionIndex: Int = 0
    @Published var inputSelectionIndex: Int = 0
    @Published var voiceModeIndex: Int = 0
    @Published var customWakeTitle: String = "自定义…"
    @Published var customInputTitle: String = "自定义…"

    @Published var launchAtLogin: Bool = false
    @Published var loginItemRequiresApproval: Bool = false
    @Published var appearanceMode: AppAppearanceMode = .system
    @Published var showMenuBarIcon: Bool = true

    @Published var mappings: ButtonMappings
    @Published var snapNoteShortcut: String? = nil
    @Published var snapNoteTagName: String = SnapNoteCoordinator.defaultTagName
    @Published var hasSnapNoteToken: Bool = false
    @Published var isSnapNoteBusy: Bool = false

    @Published var unsavedPage: SidebarTab? = nil
    private var unsavedSaveHandler: (() -> Bool)? = nil
    private var unsavedDiscardHandler: (() -> Void)? = nil

    var onAppearanceChanged: ((NSAppearance?) -> Void)?
    var onMenuBarIconPreferenceChanged: ((Bool) -> Void)?

    static var currentWindowAppearance: NSAppearance? {
        let mode = UserDefaults.standard.string(forKey: "appAppearanceMode")
            .flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        return mode.nsAppearance
    }

    private let bridge = RemoteBridge()
    private let snapTokenStore = SnapNoteTokenStore()
    private var snapAdapter: SnapNoteHelperActionAdapter?
    private var snapTask: Task<Void, Never>? {
        didSet { isSnapNoteBusy = (snapTask != nil) }
    }
    let snapShortcutKey = "snapNoteNewShortcut"
    let snapTagKey = "snapNoteTagName"
    let showMenuBarIconKey = "showMenuBarIcon"
    private let mappingStore = ButtonMappingStore()
    private lazy var buttonDispatcher = ButtonActionDispatcher(
        mappings: mappings,
        send: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 21) }
            try self.bridge.send(message)
        },
        cancelVoice: { [weak self] in self?.voice.cancelWithoutSubmitting() },
        status: { [weak self] text in self?.statusText = text }
    )
    private let output = KKCoreAudioOutput()
    private lazy var audioRouter = AudioSourceRouter(output: output, autoRefreshDevices: false)
    private var inputAppWatchdog: Timer?
    private var inputAppObservedActive = false
    private var inputAppInactiveSamples = 0
    private let keyboardSettings = KeyboardSettings()
    private var keyboardStatus = KeyboardListenerStatus()
    private var selectedDeviceUID: String?
    private var chosenInputShortcut = ShortcutDefinition(keyName: "LeftControl")!.systemShortcut

    private lazy var voice: VoiceCoordinator = VoiceCoordinator(
        beginOutput: { [weak self] session in
            guard let self, let uid = self.selectedDeviceUID else {
                throw NSError(domain: "KKvoice", code: 10, userInfo: [NSLocalizedDescriptionKey: "未选择虚拟麦克风"])
            }
            do {
                let source = try self.audioRouter.beginSession(
                    session: session,
                    virtualDeviceUID: uid,
                    remoteReady: self.voiceChannelReady
                )
                self.currentAudioSource = source
                if case .mac = source {
                    self.startInputAppWatchdog()
                }
            } catch let error as MacMicrophoneError {
                if error == .permissionDenied {
                    self.requiredPermission = "microphone"
                }
                throw error
            }
        },
        endOutput: { [weak self] session in
            guard let self else { return nil }
            self.stopInputAppWatchdog()
            self.currentAudioSource = nil
            return self.audioRouter.endSession(session: session)
        },
        command: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 11) }
            try self.bridge.send(message)
        },
        shortcut: { [weak self] in
            guard let self else { throw NSError(domain: "KKvoice", code: 12) }
            try SystemShortcutSender.send(self.chosenInputShortcut)
        },
        report: { [weak self] text in
            guard let self else { return }
            self.statusText = text
            self.syncVoicePhase()
        },
        allowKeyboardFallbackWhenNotReady: true
    )

    var canConnect: Bool { !isSessionActive && isKKvoiceMicAvailable && !isDriverInstalling }
    var canDisconnect: Bool { isSessionActive }
    var canCaptureShortcut: Bool { !isSessionActive }
    var isControlsLocked: Bool { isSessionActive }
    var isKKvoiceMicAvailable: Bool {
        availableDevices.contains(where: { $0.uid == DriverInstaller.deviceUID })
    }

    var wakeKeyTitles: [String] {
        ["不启用"] + InputShortcut.choices.map(\.name) + [customWakeTitle]
    }

    var inputKeyTitles: [String] {
        InputShortcut.choices.map(\.name) + [customInputTitle]
    }

    static let voiceModeTitles = [
        "按一次开始，再按一次结束",
        "短按切换，长按松开结束"
    ]

    init(autoRefreshDevices: Bool = true) {
        let initialMappings = mappingStore.load()
        self.mappings = initialMappings
        self.voiceModeIndex = UserDefaults.standard.bool(forKey: "remoteHybridGesture") ? 1 : 0
        self.wakeSelectionIndex = keyboardSettings.wakeSelection(choices: InputShortcut.choices)
        self.inputSelectionIndex = keyboardSettings.inputSelection(choices: InputShortcut.choices)
        self.snapNoteShortcut = UserDefaults.standard.string(forKey: snapShortcutKey)
        if let storedTag = UserDefaults.standard.string(forKey: snapTagKey),
           SnapNoteCoordinator.validTagName(storedTag) {
            self.snapNoteTagName = storedTag.trimmingCharacters(in: .whitespaces)
        } else {
            self.snapNoteTagName = SnapNoteCoordinator.defaultTagName
        }
        self.hasSnapNoteToken = snapTokenStore.exists()

        let storedAppearance = UserDefaults.standard.string(forKey: "appAppearanceMode")
            .flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        self.appearanceMode = storedAppearance

        if UserDefaults.standard.object(forKey: showMenuBarIconKey) == nil {
            self.showMenuBarIcon = true
        } else {
            self.showMenuBarIcon = UserDefaults.standard.bool(forKey: showMenuBarIconKey)
        }

        let serviceStatus = SMAppService.mainApp.status
        self.launchAtLogin = (serviceStatus == .enabled)
        self.loginItemRequiresApproval = (serviceStatus == .requiresApproval)

        bridge.onStatus = { [weak self] text in
            self?.statusText = text
        }
        bridge.onMessage = { [weak self] message in
            self?.handleHelperMessage(message)
        }
        buttonDispatcher.createSnapNote = { [weak self] in
            self?.createSnapNote()
        }
        self.selectedMacMicUID = audioRouter.selectedMacMicUID
        audioRouter.onPermissionDenied = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.requiredPermission = "microphone"
                self.currentAudioSource = nil
                self.voice.audioFailed("需要麦克风权限")
                self.connectionPhase = .permissionRequired("microphone")
            }
        }

        updateCustomShortcutTitles()
        if autoRefreshDevices {
            refreshDevices()
        }
    }

    // MARK: - Unsaved Changes Guard

    func registerUnsavedChanges(
        for page: SidebarTab,
        hasChanges: Bool,
        onSave: @escaping () -> Bool,
        onDiscard: @escaping () -> Void
    ) {
        if hasChanges {
            unsavedPage = page
            unsavedSaveHandler = onSave
            unsavedDiscardHandler = onDiscard
        } else if unsavedPage == page {
            unsavedPage = nil
            unsavedSaveHandler = nil
            unsavedDiscardHandler = nil
        }
    }

    func clearUnsavedChanges(for page: SidebarTab) {
        if unsavedPage == page {
            unsavedPage = nil
            unsavedSaveHandler = nil
            unsavedDiscardHandler = nil
        }
    }

    func confirmDiscardOrSaveIfNeeded() -> Bool {
        guard unsavedPage != nil else { return true }
        let alert = NSAlert()
        alert.messageText = "有未保存的修改"
        alert.informativeText = "是否在离开当前页面前保存修改？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        alert.window.appearance = Self.currentWindowAppearance

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let ok = unsavedSaveHandler?() ?? true
            if ok {
                unsavedPage = nil
                unsavedSaveHandler = nil
                unsavedDiscardHandler = nil
            }
            return ok
        case .alertSecondButtonReturn:
            unsavedDiscardHandler?()
            unsavedPage = nil
            unsavedSaveHandler = nil
            unsavedDiscardHandler = nil
            return true
        default:
            return false
        }
    }

    func requestSelectTab(_ tab: SidebarTab) {
        guard tab != selectedTab else { return }
        guard confirmDiscardOrSaveIfNeeded() else { return }
        selectedTab = tab
    }

    // MARK: - Devices & Shortcuts

    func refreshDevices() {
        do {
            // Restrict UI to known loopback devices, never speakers or the Mac mic.
            availableDevices = try KKAudioOutputDevices.list().filter {
                $0.uid == "KKvoiceMi2ch_UID" || $0.uid == "vRemoteDr2ch_UID" || $0.name.localizedCaseInsensitiveContains("BlackHole")
            }
            deviceLoadFailed = false
            if let index = availableDevices.firstIndex(where: { $0.uid == "KKvoiceMi2ch_UID" }) {
                selectedDeviceIndex = index
            } else if let index = availableDevices.firstIndex(where: { $0.uid == "vRemoteDr2ch_UID" }) {
                selectedDeviceIndex = index
            } else {
                selectedDeviceIndex = 0
            }
        } catch {
            availableDevices = []
            selectedDeviceIndex = 0
            deviceLoadFailed = true
            statusText = "读取音频设备失败：\(error)"
        }
        refreshMacMics()
    }

    func refreshMacMics() {
        audioRouter.refreshMacMics()
        availableMacMics = audioRouter.availableMacMics
        selectedMacMicUID = audioRouter.selectedMacMicUID
    }

    func selectSystemDefaultMacMic() {
        audioRouter.selectSystemDefaultMacMic()
        selectedMacMicUID = audioRouter.selectedMacMicUID
    }

    func selectMacMic(uid: String) {
        audioRouter.selectMacMic(uid: uid)
        selectedMacMicUID = audioRouter.selectedMacMicUID
    }

    var selectedMacMicTitle: String {
        audioRouter.selectedMacMicTitle
    }

    var activeOrStandbySource: AudioSource {
        if let currentAudioSource {
            return currentAudioSource
        }
        return audioRouter.activeOrStandbySource(remoteReady: voiceChannelReady)
    }

    func installDriver(reinstall: Bool = false, autoConnectAfterInstall: Bool = false) {
        guard !isDriverInstalling else { return }
        guard !isSessionActive else {
            statusText = "断开遥控器后可安装驱动"
            return
        }
        isDriverInstalling = true
        driverInstallError = nil
        driverInstallMessage = reinstall ? "正在重新安装 KKvoice Mic…" : "正在安装 KKvoice Mic…"
        statusText = driverInstallMessage ?? "正在安装驱动…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await DriverInstaller.install()
                self.refreshDevices()
                self.isDriverInstalling = false
                self.driverInstallError = nil
                self.driverInstallMessage = "KKvoice Mic 已就绪"
                self.statusText = "KKvoice Mic 已安装"
                if autoConnectAfterInstall && self.canConnect {
                    self.connect()
                }
            } catch {
                self.isDriverInstalling = false
                self.driverInstallMessage = nil
                let message = error.localizedDescription
                self.driverInstallError = message
                self.statusText = message
            }
        }
    }

    @discardableResult
    func checkAndPromptDriverOnLaunch() -> Bool {
        if isKKvoiceMicAvailable || DriverInstaller.isDeviceAvailable {
            return true
        }
        statusText = "需要安装 KKvoice Mic"
        let alert = NSAlert()
        alert.messageText = "需要安装 KKvoice Mic 才能使用"
        alert.informativeText = "点击「安装」并授权管理员权限，即可完成内置虚拟麦克风驱动安装。"
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "稍后")
        alert.window.appearance = Self.currentWindowAppearance
        if alert.runModal() == .alertFirstButtonReturn {
            installDriver(reinstall: false, autoConnectAfterInstall: true)
        }
        return false
    }

    func deviceDisplayTitle(_ device: KKAudioOutputDevice) -> String {
        device.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var emptyDevicePlaceholderTitle: String {
        deviceLoadFailed ? "读取设备失败" : "无可用虚拟麦克风"
    }

    func selectWakeKey(at index: Int) {
        let choices = InputShortcut.choices
        if index == choices.count + 1 {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.wakeDefinition(), globalWake: true) {
                keyboardSettings.saveWakeDefinition(value)
            }
        } else {
            keyboardSettings.saveWake(selection: index, choices: choices)
        }
        wakeSelectionIndex = keyboardSettings.wakeSelection(choices: choices)
        updateCustomShortcutTitles()
    }

    func promptCustomWakeShortcut() {
        guard canCaptureShortcut else { return }
        if let value = ShortcutPicker.prompt(previous: keyboardSettings.wakeDefinition(), globalWake: true) {
            keyboardSettings.saveWakeDefinition(value)
        }
        wakeSelectionIndex = keyboardSettings.wakeSelection(choices: InputShortcut.choices)
        updateCustomShortcutTitles()
    }

    func selectInputKey(at index: Int) {
        let choices = InputShortcut.choices
        if index == choices.count {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.inputDefinition(), globalWake: false) {
                keyboardSettings.saveInputDefinition(value)
            }
        } else {
            keyboardSettings.saveInput(selection: index, choices: choices)
        }
        inputSelectionIndex = keyboardSettings.inputSelection(choices: choices)
        updateCustomShortcutTitles()
    }

    func promptCustomInputShortcut() {
        guard canCaptureShortcut else { return }
        if let value = ShortcutPicker.prompt(previous: keyboardSettings.inputDefinition(), globalWake: false) {
            keyboardSettings.saveInputDefinition(value)
        }
        inputSelectionIndex = keyboardSettings.inputSelection(choices: InputShortcut.choices)
        updateCustomShortcutTitles()
    }

    func selectVoiceMode(at index: Int) {
        voiceModeIndex = index
        UserDefaults.standard.set(index == 1, forKey: "remoteHybridGesture")
    }

    func updateCustomShortcutTitles() {
        let choices = InputShortcut.choices
        if keyboardSettings.wakeSelection(choices: choices) == choices.count + 1,
           let definition = keyboardSettings.wakeDefinition() {
            customWakeTitle = "自定义：\(definition.displayString)"
        } else {
            customWakeTitle = "自定义…"
        }
        if keyboardSettings.inputSelection(choices: choices) == choices.count {
            customInputTitle = "自定义：\(keyboardSettings.inputDefinition().displayString)"
        } else {
            customInputTitle = "自定义…"
        }
    }

    // MARK: - Appearance, Menu Bar & Login Item

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "appAppearanceMode")
        applyAppearance()
    }

    func cycleAppearanceMode() {
        let next: AppAppearanceMode
        switch appearanceMode {
        case .system: next = .light
        case .light: next = .dark
        case .dark: next = .system
        }
        setAppearanceMode(next)
    }

    func applyAppearance() {
        // Apply ONLY to the app's own windows (via onAppearanceChanged), NEVER to
        // NSApplication.shared.appearance or NSStatusBarWindow so the menu-bar
        // template icon always tints according to the wallpaper/menu bar.
        let target = appearanceMode.nsAppearance
        onAppearanceChanged?(target)
    }

    func setShowMenuBarIcon(_ enabled: Bool) {
        showMenuBarIcon = enabled
        UserDefaults.standard.set(enabled, forKey: showMenuBarIconKey)
        onMenuBarIconPreferenceChanged?(enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            let current = SMAppService.mainApp.status
            launchAtLogin = current == .enabled
            loginItemRequiresApproval = current == .requiresApproval
            if current == .requiresApproval {
                statusText = "需在系统设置「登录项」中允许"
            }
        } catch {
            let current = SMAppService.mainApp.status
            launchAtLogin = current == .enabled
            loginItemRequiresApproval = current == .requiresApproval
            statusText = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Connection & SnapNote

    func connect() {
        guard !isSessionActive else { return }
        guard isKKvoiceMicAvailable else {
            statusText = "需要安装 KKvoice Mic"
            return
        }
        guard !isDriverInstalling else { return }
        guard let resourceURL = Bundle.main.resourceURL else {
            statusText = "找不到应用资源。"
            return
        }
        let index = selectedDeviceIndex
        selectedDeviceUID = availableDevices.indices.contains(index) ? availableDevices[index].uid : nil
        chosenInputShortcut = keyboardSettings.inputDefinition().systemShortcut
        let wakeDefinition = keyboardSettings.wakeDefinition()
        guard voice.setRemoteGesture(voiceModeIndex == 1 ? .hybrid : .toggle) else {
            statusText = "收音中，无法操作"
            return
        }
        // Start the remote audio route before Vokie receives its toggle. Passing
        // through the physical key can make Vokie open the input before CoreAudio
        // has attached to the virtual microphone, which yields an empty recording.
        let passThrough = false
        guard voice.setKeyboardPassThrough(passThrough) else {
            statusText = "收音中，无法操作"
            return
        }
        let selectedWake = wakeDefinition?.keyName
        let helper = resourceURL.appendingPathComponent("KKvoiceRemoteHelper.app/Contents/MacOS/KKvoiceRemoteHelper")
        do {
            requiredPermission = nil
            keyboardStatus.connecting(key: selectedWake)
            keyboardState = keyboardStatus.state
            keyboardStatusText = keyboardStatus.text
            connectionPhase = .connecting
            try bridge.start(
                helperURL: helper,
                keyboardKey: selectedWake,
                keyboardModifiers: wakeDefinition?.modifiers ?? [],
                keyboardPassThrough: passThrough
            )
            snapAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported: true) { [weak self] message in
                DispatchQueue.main.async { [weak self] in
                    do { try self?.bridge.send(message.wireFields) }
                    catch { Task { await self?.snapAdapter?.helperDisconnected() } }
                }
            }
            isSessionActive = true
        } catch {
            keyboardStatus.receive(["type": "helper_process_exited"])
            keyboardState = keyboardStatus.state
            keyboardStatusText = keyboardStatus.text
            isSessionActive = false
            connectionPhase = .error(error.localizedDescription)
            bridge.stop()
            statusText = error.localizedDescription
        }
    }

    func disconnect() {
        stopInputAppWatchdog()
        snapTask?.cancel()
        if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
        snapAdapter = nil
        voice.cancel()
        voice.setReady(false)
        _ = audioRouter.endSession()
        currentAudioSource = nil
        bridge.stop()
    }

    func applyMappings(_ newMappings: ButtonMappings) throws {
        try mappingStore.save(newMappings)
        mappings = newMappings
        buttonDispatcher.mappings = newMappings
    }

    func pickSnapNoteShortcut(currentEncoded: String? = nil) -> String? {
        guard canCaptureShortcut else {
            statusText = "断开遥控器后可修改"
            return nil
        }
        let source = currentEncoded ?? UserDefaults.standard.string(forKey: snapShortcutKey)
        let previous = source.flatMap(ShortcutDefinition.init(encoded:))
        guard let selected = ShortcutPicker.prompt(previous: previous, globalWake: false),
              SnapNoteCoordinator.validShortcut(selected.encoded) else {
            statusText = "新建快捷键需包含修饰键"
            return nil
        }
        return selected.encoded
    }

    @discardableResult
    func saveSnapNoteConfiguration(
        token: String,
        shortcutEncoded: String?,
        tagName: String? = nil
    ) -> Bool {
        guard canCaptureShortcut else {
            statusText = "断开遥控器后可修改"
            return false
        }
        let resolvedTag = (tagName ?? snapNoteTagName).trimmingCharacters(in: .whitespaces)
        guard SnapNoteCoordinator.validTagName(resolvedTag) else {
            statusText = "标签需为 1–20 字单行文字"
            return false
        }
        do {
            if !token.isEmpty {
                try snapTokenStore.save(token)
                hasSnapNoteToken = true
            }
            guard let encoded = shortcutEncoded,
                  SnapNoteCoordinator.validShortcut(encoded) else {
                statusText = "新建快捷键需包含修饰键"
                return false
            }
            UserDefaults.standard.set(encoded, forKey: snapShortcutKey)
            UserDefaults.standard.set(resolvedTag, forKey: snapTagKey)
            snapNoteShortcut = encoded
            snapNoteTagName = resolvedTag
            statusText = "已保存"
            return true
        } catch {
            statusText = "Token 保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func createSnapNote() {
        guard snapTask == nil else { statusText = "正在创建闪念笔记…"; return }
        guard let adapter = snapAdapter else { statusText = "未连接遥控器"; return }
        guard case .idle = voice.phase else { statusText = "收音中，无法操作"; return }
        guard let shortcut = UserDefaults.standard.string(forKey: snapShortcutKey) else {
            statusText = "未设置闪念笔记快捷键"
            return
        }
        let rawTag = UserDefaults.standard.string(forKey: snapTagKey) ?? snapNoteTagName
        let tagName = SnapNoteCoordinator.validTagName(rawTag)
            ? rawTag.trimmingCharacters(in: .whitespaces)
            : SnapNoteCoordinator.defaultTagName
        do {
            guard let token = try snapTokenStore.load() else {
                statusText = "未配置闪念笔记 Token"
                return
            }
            let client = try SnapNoteMCPClient(token: token)
            let coordinator = SnapNoteCoordinator(client: client, native: adapter, isRecording: { [weak self] in
                await self?.isVoiceActive() ?? true
            })
            statusText = "正在新建闪念笔记…"
            snapTask = Task { @MainActor [weak self] in
                let result = await coordinator.createAndTag(shortcut: shortcut, tagName: tagName)
                guard let self else { return }
                self.snapTask = nil
                if result.succeeded {
                    self.statusText = "已创建闪念笔记"
                } else if result.noteMayExist {
                    self.statusText = "操作未完成，笔记可能已创建"
                } else {
                    self.statusText = "闪念操作未完成：\(String(describing: result.error))"
                }
            }
        } catch {
            statusText = "闪念笔记配置不可用。"
        }
    }

    private func isVoiceActive() -> Bool {
        if case .idle = voice.phase { return false }
        return true
    }

    func handleHelperMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String,
           let raw = message["actionId"] as? String,
           let id = UUID(uuidString: raw),
           let adapter = snapAdapter {
            let prevented = message["prevented"] as? Bool
            Task { await adapter.handleHelperEvent(type: type, actionID: id, prevented: prevented) }
        }
        keyboardStatus.receive(message)
        keyboardState = keyboardStatus.state
        keyboardStatusText = keyboardStatus.text
        switch message["type"] as? String {
        case "device_ready":
            voice.setReady(true)
            voiceChannelReady = true
            requiredPermission = nil
            statusText = "已连接"
            syncVoicePhase()
        case "hid_connected":
            hidConnected = true
            statusText = "按键已连接"
            syncVoicePhase()
        case "scanning":
            statusText = "正在连接…"
            if !voiceChannelReady && !hidConnected {
                connectionPhase = .connecting
            }
        case "ble_disconnected", "bluetooth_off":
            voice.setReady(false)
            voiceChannelReady = false
            statusText = "蓝牙已断开"
            syncVoicePhase()
        case "hid_disconnected":
            buttonDispatcher.deviceDisconnected()
            hidConnected = false
            lastPressedButtonID = nil
            statusText = "按键已断开"
            syncVoicePhase()
        case "button_down":
            if let id = message["buttonId"] as? String {
                let upper = id.uppercased()
                lastPressedButtonID = upper
                buttonDispatcher.down(upper)
            }
        case "button_up":
            if let id = message["buttonId"] as? String {
                let upper = id.uppercased()
                if lastPressedButtonID == upper { lastPressedButtonID = nil }
                buttonDispatcher.up(upper)
            }
        case "app_switcher_state":
            buttonDispatcher.switcherActive = message["active"] as? Bool == true
        case "action_error":
            statusText = message["message"] as? String ?? "按键动作失败。"
        case "voice_press":
            guard snapTask == nil else {
                statusText = "正在创建闪念笔记，稍后再试"
                return
            }
            voice.press(.remote)
            syncVoicePhase()
        case "voice_release":
            voice.release(.remote)
            syncVoicePhase()
        case "keyboard_trigger_down":
            guard snapTask == nil else {
                statusText = "正在创建闪念笔记，稍后再试"
                return
            }
            voice.press(.keyboard)
            syncVoicePhase()
        case "keyboard_trigger_up":
            if message["interrupted"] as? Bool == true {
                voice.keyboardInterrupted()
            } else {
                voice.release(.keyboard)
            }
            syncVoicePhase()
        case "keyboard_cancel_session":
            voice.cancelWithoutSubmitting()
            syncVoicePhase()
        case "capture_probe_started":
            statusText = "正在启动收音…"
        case "capture_probe_timeout":
            statusText = "收音未启动"
            syncVoicePhase()
        case "audio_start":
            voice.audioStarted()
            recordingFrames = 0
            syncVoicePhase()
        case "audio_reopen_requested":
            statusText = "正在恢复收音…"
        case "audio_stream_progress":
            if case .recording = voice.phase, let frames = message["frames"] as? Int {
                recordingFrames = frames
                statusText = "收音中（\(frames) 帧）"
                startInputAppWatchdog()
            }
            syncVoicePhase()
        case "audio_frame":
            guard message["sampleRate"] as? Int == 16_000,
                  let encoded = message["pcmBase64"] as? String,
                  let pcm = Data(base64Encoded: encoded) else { return }
            _ = audioRouter.receiveRemotePCM(pcm)
        case "mic_open_error":
            if let code = message["code"] as? NSNumber {
                voice.audioFailed("麦克风开启失败（\(code.uint64Value)）")
            } else {
                voice.audioFailed("麦克风开启失败")
            }
            syncVoicePhase()
        case "permission_required":
            voice.setReady(false)
            voiceChannelReady = false
            let perm = message["permission"] as? String ?? "unknown"
            requiredPermission = perm
            switch perm {
            case "accessibility":
                statusText = "需要辅助功能权限"
            case "input-monitoring":
                statusText = "需要输入监控权限"
            case "bluetooth":
                statusText = "需要蓝牙权限"
            default:
                statusText = "需要系统权限"
            }
            connectionPhase = .permissionRequired(perm)
        case "device_error", "device_not_found":
            voice.setReady(false)
            voiceChannelReady = false
            let errMsg = message["message"] as? String ?? "遥控器暂不可用"
            statusText = errMsg
            connectionPhase = .error(errMsg)
        case "helper_process_exited":
            stopInputAppWatchdog()
            snapTask?.cancel()
            if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
            snapAdapter = nil
            buttonDispatcher.reset()
            voice.cancel()
            voice.setReady(false)
            _ = audioRouter.endSession()
            currentAudioSource = nil
            isSessionActive = false
            hidConnected = false
            voiceChannelReady = false
            isRecording = false
            recordingFrames = 0
            lastPressedButtonID = nil
            if requiredPermission == nil {
                connectionPhase = .disconnected
            }
        default:
            break
        }
    }

    private func syncVoicePhase() {
        switch voice.phase {
        case .recording:
            isRecording = true
            connectionPhase = .recording
        case .starting, .stopping:
            isRecording = false
            if voiceChannelReady {
                connectionPhase = .voiceReady
            }
        case .idle:
            isRecording = false
            recordingFrames = 0
            if let perm = requiredPermission {
                connectionPhase = .permissionRequired(perm)
            } else if voiceChannelReady {
                connectionPhase = .voiceReady
            } else if hidConnected {
                connectionPhase = .keysConnected
            } else if isSessionActive {
                connectionPhase = .connecting
            } else {
                connectionPhase = .disconnected
            }
        }
    }

    private func startInputAppWatchdog() {
        guard inputAppWatchdog == nil else { return }
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
        inputAppWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                guard case .recording = self.voice.phase else {
                    self.stopInputAppWatchdog()
                    return
                }
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
                    self.statusText = "输入软件已结束，收音已停止"
                    self.syncVoicePhase()
                }
            }
        }
    }

    private func stopInputAppWatchdog() {
        inputAppWatchdog?.invalidate()
        inputAppWatchdog = nil
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
    }

    var activePermissionIssue: String? {
        if let requiredPermission {
            return requiredPermission
        }
        if keyboardState == .permissionRequired {
            return "accessibility"
        }
        return nil
    }

    func permissionTitle(for permission: String) -> String {
        switch permission {
        case "accessibility":
            return "需要辅助功能权限"
        case "input-monitoring":
            return "需要输入监控权限"
        case "bluetooth":
            return "需要蓝牙权限"
        case "microphone":
            return "需要麦克风权限"
        default:
            return "需要系统权限"
        }
    }

    func permissionDescription(for permission: String) -> String {
        switch permission {
        case "accessibility":
            return "在「隐私与安全性 › 辅助功能」中允许 KKvoice Remote Helper"
        case "input-monitoring":
            return "在「隐私与安全性 › 输入监控」中允许 KKvoice Remote Helper"
        case "bluetooth":
            return "在「隐私与安全性 › 蓝牙」中允许 KKvoice Remote Helper"
        case "microphone":
            return "在「隐私与安全性 › 麦克风」中允许 KKvoice"
        default:
            return "检查「隐私与安全性」权限设置"
        }
    }

    func openPermissionSettings(for permission: String? = nil) {
        let target = permission ?? activePermissionIssue ?? ""
        let urlString: String
        switch target {
        case "accessibility":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "input-monitoring":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case "bluetooth":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case "microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case "login-items":
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openExternalURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private static var fallbackPlistDictionary: [String: Any]? = {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Native/Info.plist")
        return NSDictionary(contentsOf: plistURL) as? [String: Any]
    }()

    var appVersionString: String {
        if let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return short
        }
        if let short = Self.fallbackPlistDictionary?["CFBundleShortVersionString"] as? String {
            return short
        }
        return ""
    }

    var appBuildString: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        if let build = Self.fallbackPlistDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return ""
    }
}
