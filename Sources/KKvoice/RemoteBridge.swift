import Foundation

/// Newline-delimited JSON emitted by the existing remote helper. Partial pipe
/// reads and multiple messages in one read are both normal.
struct JSONLineDecoder {
    private var pending = Data()
    private let maximumLineBytes = 2 * 1024 * 1024

    mutating func append(_ bytes: Data) -> [[String: Any]] {
        pending.append(bytes)
        var messages: [[String: Any]] = []
        while let newline = pending.firstIndex(of: 0x0a) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            guard line.count <= maximumLineBytes,
                  let value = try? JSONSerialization.jsonObject(with: line),
                  let object = value as? [String: Any] else { continue }
            messages.append(object)
        }
        // A malformed or unbounded stream cannot grow memory indefinitely.
        if pending.count > maximumLineBytes { pending.removeAll() }
        return messages
    }
}

/// Owns exactly one helper process. It does not begin audio capture; a future
/// session coordinator may send ensure_capture/stop_capture explicitly.
final class RemoteBridge {
    var onMessage: (([String: Any]) -> Void)?
    var onStatus: ((String) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var decoder = JSONLineDecoder()
    private let readingQueue = DispatchQueue(label: "local.kkvoice.helper-output")

    func start(helperURL: URL, keyboardKey: String? = nil, keyboardModifiers: [String] = [], keyboardPassThrough: Bool = false) throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw NSError(domain: "KKvoice.RemoteBridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到遥控器助手，请重新构建应用。"])
        }
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        child.executableURL = helperURL
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.standardError
        child.terminationHandler = { [weak self, weak child] _ in
            DispatchQueue.main.async {
                guard let self, let child, self.process === child else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.input = nil
                self.output = nil
                self.onStatus?("遥控器助手已停止")
                self.onMessage?(["type": "helper_process_exited"])
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] file in
            let bytes = file.availableData
            guard !bytes.isEmpty else { return }
            self?.readingQueue.async { [weak self] in
                guard let self else { return }
                let messages = self.decoder.append(bytes)
                DispatchQueue.main.async { [weak self] in
                    for message in messages { self?.onMessage?(message) }
                }
            }
        }
        do { try child.run() } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        process = child
        input = stdinPipe
        output = stdoutPipe
        onStatus?("正在连接遥控器…")
        // Stage 1 enables device discovery only. It does not seize a keyboard
        // trigger or configure key actions until the user explicitly opts in.
        try send(["type": "configure", "config": [
            "hidSource": "iokit",
            "keyboardTrigger": ["enabled": keyboardKey != nil, "key": keyboardKey ?? "Fn", "modifiers": keyboardModifiers, "captureCancelOnly": false, "passThrough": keyboardPassThrough],
            "buttonMappings": [:]
        ]])
    }

    func send(_ message: [String: Any]) throws {
        guard let input, process?.isRunning == true else {
            throw NSError(domain: "KKvoice.RemoteBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "遥控器助手未运行。"])
        }
        var line = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        line.append(0x0a)
        try input.fileHandleForWriting.write(contentsOf: line)
    }

    func stop() {
        guard let child = process else { return }
        try? send(["type": "shutdown"])
        try? input?.fileHandleForWriting.close()
        onStatus?("正在断开遥控器…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak child] in
            guard let self, let child, self.process === child, child.isRunning else { return }
            child.terminate()
        }
    }
}
