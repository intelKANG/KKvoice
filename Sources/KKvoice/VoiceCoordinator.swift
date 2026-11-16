import Foundation
import VoiceSessions

/// Calls are serialized on the main thread. The legacy helper does not attach
/// session IDs to its BLE notifications; stale event behavior requires device testing.
final class VoiceCoordinator {
    typealias BeginOutput = (UUID) throws -> Void
    typealias EndOutput = (UUID) -> String?
    private var session = VoiceSession()
    private var relay = ShortcutRelay()
    private let beginOutput: BeginOutput
    private let endOutput: EndOutput
    private let command: ([String: Any]) throws -> Void
    private let shortcut: () throws -> Void
    private let report: (String) -> Void
    private var activeID: UUID?
    private var ready = false
    private var keyboardHeld = false
    private var keyboardPassThrough = false
    private var passedThroughWhileUnavailable = false
    private var deferredToggle: UUID?
    private var timeoutWork: DispatchWorkItem?
    private var needsRecovery = false

    init(beginOutput: @escaping BeginOutput, endOutput: @escaping EndOutput,
         command: @escaping ([String: Any]) throws -> Void,
         shortcut: @escaping () throws -> Void, report: @escaping (String) -> Void) {
        self.beginOutput = beginOutput; self.endOutput = endOutput
        self.command = command; self.shortcut = shortcut; self.report = report
    }
    var phase: VoiceSession.Phase { session.phase }
    @discardableResult func setRemoteGesture(_ gesture: VoiceSession.RemoteGesture) -> Bool {
        session.setRemoteGesture(gesture)
    }
    /// Configure only after the host has established that the physical wake
    /// key exactly matches the input application's single-key shortcut.
    /// Pass-through means the event is allowed through, not proven delivered.
    /// Configure while idle, before enabling the helper's keyboard tap.
    @discardableResult func setKeyboardPassThrough(_ enabled: Bool) -> Bool {
        guard case .idle = session.phase, !keyboardHeld, deferredToggle == nil else { return false }
        keyboardPassThrough = enabled
        return true
    }
    /// Call only after the user has checked that the input application stopped.
    @discardableResult func acknowledgeInputSoftwareStopped() -> Bool {
        guard case .idle = session.phase, !keyboardHeld, deferredToggle == nil else { return false }
        passedThroughWhileUnavailable = false
        needsRecovery = false
        return true
    }
    private var keyboardOrigin: ShortcutRelay.Origin {
        keyboardPassThrough ? .keyboardDelivered : .keyboardConsumed
    }
    func setReady(_ value: Bool) {
        ready = value
        if value {
            if case .idle = session.phase, !passedThroughWhileUnavailable { needsRecovery = false }
        } else {
            cancel()
            if deferredToggle != nil {
                deferredToggle = nil
                needsRecovery = true
                report("唤醒键状态中断，请手动检查输入软件。")
            }
            keyboardHeld = false
        }
    }
    func press(_ source: VoiceSession.Source) {
        if source == .keyboard { keyboardHeld = true }
        guard ready else {
            if source == .keyboard && keyboardPassThrough {
                passedThroughWhileUnavailable = true
                needsRecovery = true
                report("物理快捷键已透传，但遥控器未就绪；请确认输入软件已停止。")
            } else { report("遥控器尚未连接。") }
            return
        }
        guard deferredToggle == nil else { report("等待释放唤醒键。") ; return }
        guard !needsRecovery else { report("输入软件状态未确认，请先检查并确认已停止。") ; return }
        apply(relay.handle(session.press(source, at: ProcessInfo.processInfo.systemUptime),
                           origin: source == .keyboard ? keyboardOrigin : .remote))
    }
    func release(_ source: VoiceSession.Source) {
        if source == .keyboard { keyboardHeld = false }
        apply(relay.handle(session.release(source, at: ProcessInfo.processInfo.systemUptime),
                           origin: source == .keyboard ? keyboardOrigin : .remote))
        if source == .keyboard {
            if let id = deferredToggle { deferredToggle = nil; apply([.sendToggle(id)]) }
            if case .recording(let id) = session.phase, activeID == id { apply(relay.audioReady(id)) }
        }
    }
    /// The helper emits an interrupted key-up when the event tap times out or
    /// restarts. It is NOT a physical release: never flush a deferred toggle.
    func keyboardInterrupted() {
        guard keyboardHeld else { return }
        keyboardHeld = false
        deferredToggle = nil
        if let id = activeID { apply(relay.failed(id)) }
        apply(relay.handle(session.cancel(), origin: .remote))
        passedThroughWhileUnavailable = true
        needsRecovery = true
        report("唤醒键监听中断，请检查输入软件已停止后再恢复。")
    }
    func audioStarted() {
        guard case .starting(let id) = session.phase, activeID == id else { return }
        timeoutWork?.cancel(); timeoutWork = nil
        _ = session.didStart(id)
        if !keyboardHeld { apply(relay.audioReady(id)) }
        guard session.phase == .recording(id), !needsRecovery else { return }
        report(keyboardHeld ? "遥控器已准备好，等待释放唤醒键。" : "遥控器收音中；识别状态以输入软件为准。")
    }
    func cancel() { apply(relay.handle(session.cancel(), origin: .remote)) }
    func cancelWithoutSubmitting() {
        guard let id = activeID else { report("当前没有正在收音的会话。"); return }
        relay.cancelled(id)
        apply(relay.handle(session.cancel(), origin: .remote))
        passedThroughWhileUnavailable = false
        needsRecovery = false
        report("已停止收音，请在输入软件中手动取消转录，并确认其已停止。")
    }
    func audioFailed(_ message: String) {
        if let id = activeID { apply(relay.failed(id)) }
        cancel(); report(message)
    }

    private func apply(_ actions: [ShortcutRelay.Action]) {
        for action in actions {
            switch action {
            case .capture(.begin(let id)):
                do {
                    activeID = id
                    try command(["type": "ensure_capture"])
                    try command(["type": "set_escape_cancel", "enabled": true])
                    // Authorize the helper's short START_SEARCH/AUDIO_START probe
                    // before opening CoreAudio. AudioDeviceStart can block long
                    // enough for the helper's probe deadline to expire.
                    try beginOutput(id)
                    report("正在启动收音…")
                    let timeout = DispatchWorkItem { [weak self] in
                        guard let self, self.phase == .starting(id) else { return }
                        self.audioFailed("遥控器收音启动超时。")
                    }
                    timeoutWork = timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
                } catch {
                    activeID = id
                    // The helper may already have been authorized; cancel both
                    // sides before reporting the failed start.
                    apply(relay.failed(id))
                    apply(relay.handle(session.cancel(), origin: .remote))
                    report(error.localizedDescription)
                }
            case .capture(.end(let id)):
                guard activeID == id else { continue }
                timeoutWork?.cancel(); timeoutWork = nil
                try? command(["type": "stop_capture"])
                try? command(["type": "set_escape_cancel", "enabled": false])
                let releaseError = endOutput(id)
                activeID = nil
                session.didStop(id)
                if let releaseError {
                    needsRecovery = true
                    report("音频设备释放失败：\(releaseError)")
                } else { report("收音已结束。") }
            case .sendToggle(let id):
                if keyboardHeld { deferredToggle = id; break }
                // End toggles are generated after capture teardown; starts only
                // after audioStarted and, for keyboard, physical key release.
                do { try shortcut() }
                catch {
                    apply(relay.failed(id))
                    if activeID == id { apply(relay.handle(session.cancel(), origin: .remote)) }
                    report("快捷键发送失败：\(error.localizedDescription)")
                }
            case .synchronizationUncertain:
                needsRecovery = true
                report("无法确认输入软件状态，请手动检查；重新连接后再试。")
            }
        }
    }
}
