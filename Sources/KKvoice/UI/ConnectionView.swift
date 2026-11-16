import RemoteAudio
import SwiftUI
import VoiceSessions

struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @State private var pulseRing = false

    private var wakeBinding: Binding<Int> {
        Binding(
            get: { model.wakeSelectionIndex },
            set: { model.selectWakeKey(at: $0) }
        )
    }

    private var inputBinding: Binding<Int> {
        Binding(
            get: { model.inputSelectionIndex },
            set: { model.selectInputKey(at: $0) }
        )
    }

    private var voiceModeBinding: Binding<Int> {
        Binding(
            get: { model.voiceModeIndex },
            set: { model.selectVoiceMode(at: $0) }
        )
    }

    private var remoteHighlightedID: String? {
        if model.isRecording {
            return "voice"
        }
        return model.lastPressedButtonID
    }

    var body: some View {
        PageScaffold(
            title: "连接与语音",
            subtitle: "连接 Chromecast / Google TV 语音遥控器，使用所选输入软件的语音快捷键"
        ) {
            StatusPill(
                title: model.connectionPhase.badgeTitle,
                tone: model.connectionPhase.tone,
                systemImage: phaseSymbol
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.s16) {
                HStack(alignment: .top, spacing: DS.s20) {
                    deviceHeroCard
                        .frame(width: 286)

                    VStack(alignment: .leading, spacing: DS.s16) {
                        statusCard
                        voiceSettingsCard
                    }
                    .frame(maxWidth: .infinity)
                }

                footerNote
            }
        }
    }

    private var phaseSymbol: String {
        switch model.connectionPhase {
        case .disconnected:
            return "bolt.slash"
        case .connecting:
            return "dot.radiowaves.left.and.right"
        case .keysConnected:
            return "dpad.fill"
        case .voiceReady:
            return "checkmark.circle.fill"
        case .recording:
            return "waveform"
        case .permissionRequired:
            return "exclamationmark.shield.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var deviceHeroCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .center, spacing: DS.s16) {
                HStack(spacing: DS.s8) {
                    GoogleAssistantDotsView(size: 14)
                    Text("Chromecast 语音遥控器")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    StatusDot(tone: model.connectionPhase.tone, size: 8)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    model.connectionPhase.tone.color.opacity(0.11),
                                    DS.subtleFill
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(model.connectionPhase.tone.color.opacity(0.20), lineWidth: 1)
                        )

                    if model.isRecording {
                        Circle()
                            .stroke(Color.blue.opacity(0.32), lineWidth: 2)
                            .frame(width: 148, height: 148)
                            .scaleEffect(pulseRing ? 1.16 : 0.86)
                            .opacity(pulseRing ? 0.15 : 0.65)
                            .animation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                value: pulseRing
                            )
                    }

                    RemoteIllustration(
                        highlighted: remoteHighlightedID,
                        compact: true
                    )
                    .padding(.vertical, DS.s12)
                }
                .frame(height: 224)
                .onAppear { pulseRing = model.isRecording }
                .onChange(of: model.isRecording) { active in
                    pulseRing = active
                }

                VStack(spacing: 4) {
                    HStack(spacing: DS.s8) {
                        StatusDot(tone: model.connectionPhase.tone, size: 9)
                        Text(model.connectionPhase.headlineTitle)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                    }
                    if model.isRecording && model.recordingFrames > 0 {
                        Text("已接收 \(model.recordingFrames) 帧音频（16 kHz PCM）")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                    } else {
                        Text(deviceSubtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                CardDivider()

                VStack(alignment: .leading, spacing: 10) {
                    channelStepRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "蓝牙链路",
                        stateText: bluetoothStepText,
                        tone: bluetoothStepTone
                    )
                    channelStepRow(
                        icon: "dpad.fill",
                        title: "按键通道",
                        stateText: hidStepText,
                        tone: hidStepTone
                    )
                    channelStepRow(
                        icon: "waveform.badge.mic",
                        title: "语音通道",
                        stateText: voiceStepText,
                        tone: voiceStepTone
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.canConnect {
                    Button {
                        model.connect()
                    } label: {
                        HStack(spacing: DS.s8) {
                            Image(systemName: "link")
                            Text("连接遥控器")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("启动助手并连接 Chromecast 遥控器")
                } else {
                    Button {
                        model.disconnect()
                    } label: {
                        HStack(spacing: DS.s8) {
                            Image(systemName: "xmark.circle")
                            Text("断开连接")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("断开遥控器并停止后台助手")
                }
            }
        }
    }

    private var deviceSubtitleText: String {
        switch model.connectionPhase {
        case .disconnected:
            return "点击下方按钮启动遥控器连接"
        case .connecting:
            return "请按遥控器任意键唤醒蓝牙连接"
        case .keysConnected:
            return "按键已响应，正在同步语音通道"
        case .voiceReady:
            return "按遥控器语音键或电脑唤醒键开始说话"
        case .recording:
            return "正在将遥控器麦克风音频写入虚拟设备"
        case .permissionRequired:
            return "授权后重新连接即可启用完整功能"
        case .error(let msg):
            return msg
        }
    }

    private var bluetoothStepTone: StatusTone {
        if let perm = model.requiredPermission, perm == "bluetooth" {
            return .warning
        }
        if model.voiceChannelReady || model.hidConnected {
            return .connected
        }
        if model.isSessionActive {
            return .connecting
        }
        return .disconnected
    }

    private var bluetoothStepText: String {
        if let perm = model.requiredPermission, perm == "bluetooth" {
            return "需蓝牙权限"
        }
        if model.voiceChannelReady || model.hidConnected {
            return "已连接"
        }
        if model.isSessionActive {
            return "正在搜索"
        }
        return "未连接"
    }

    private var hidStepTone: StatusTone {
        if let perm = model.requiredPermission, perm == "input-monitoring" || perm == "accessibility" {
            return .warning
        }
        if model.hidConnected {
            return .connected
        }
        if model.isSessionActive {
            return .connecting
        }
        return .disconnected
    }

    private var hidStepText: String {
        if let perm = model.requiredPermission, perm == "input-monitoring" {
            return "需输入监控"
        }
        if model.hidConnected {
            return "已就绪"
        }
        if model.isSessionActive {
            return "等待唤醒"
        }
        return "未连接"
    }

    private var voiceStepTone: StatusTone {
        if model.isRecording {
            return .recording
        }
        if model.voiceChannelReady {
            return .connected
        }
        if model.isSessionActive {
            return .connecting
        }
        return .disconnected
    }

    private var voiceStepText: String {
        if model.isRecording {
            return "收音中"
        }
        if model.voiceChannelReady {
            return "已就绪"
        }
        if model.isSessionActive {
            return "等待连接"
        }
        return "未连接"
    }

    private func channelStepRow(
        icon: String,
        title: String,
        stateText: String,
        tone: StatusTone
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tone.color.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.color)
            }
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 5) {
                StatusDot(tone: tone, size: 6)
                Text(stateText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tone == .disconnected ? .secondary : .primary)
            }
        }
    }

    private var statusCard: some View {
        Card(padding: DS.s16) {
            VStack(alignment: .leading, spacing: DS.s12) {
                SectionHeader("当前状态", systemImage: "waveform.path.ecg")

                if let permission = model.activePermissionIssue {
                    permissionBanner(for: permission)
                }

                HStack(alignment: .top, spacing: DS.s12) {
                    statusTile(
                        title: "连接与收音状态",
                        value: model.statusText,
                        icon: "dot.radiowaves.up.forward",
                        tone: model.connectionPhase.tone
                    )
                    statusTile(
                        title: "键盘唤醒监听",
                        value: model.keyboardStatusText,
                        icon: "keyboard",
                        tone: keyboardTone
                    )
                }
            }
        }
    }

    private var keyboardTone: StatusTone {
        switch model.keyboardState {
        case .ready:
            return .connected
        case .starting:
            return .connecting
        case .permissionRequired:
            return .warning
        case .failed:
            return .error
        case .disabled, .stopped:
            return .disconnected
        }
    }

    private func statusTile(
        title: String,
        value: String,
        icon: String,
        tone: StatusTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tone.color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusDot(tone: tone, size: 6)
            }
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.s12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                .fill(DS.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    private func permissionBanner(for permission: String) -> some View {
        HStack(alignment: .center, spacing: DS.s12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.permissionTitle(for: permission))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(model.permissionDescription(for: permission))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DS.s8)

            Button("打开系统设置") {
                model.openPermissionSettings(for: permission)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(DS.s12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var voiceSettingsCard: some View {
        Card(padding: DS.s16) {
            VStack(alignment: .leading, spacing: DS.s12) {
                SectionHeader(
                    "语音设置",
                    subtitle: "配置虚拟音频输出设备与语音输入触发方式",
                    systemImage: "slider.horizontal.3"
                ) {
                    if model.isControlsLocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("断开后可修改")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                    }
                }

                CardDivider()

                LabeledRow(
                    "虚拟麦克风",
                    subtitle: "将遥控器语音写入该虚拟设备供输入软件读取",
                    systemImage: "mic.and.signal.meter"
                ) {
                    HStack(spacing: DS.s8) {
                        if model.availableDevices.isEmpty {
                            Picker("", selection: .constant(0)) {
                                Text(model.emptyDevicePlaceholderTitle).tag(0)
                            }
                            .labelsHidden()
                            .frame(width: 240)
                            .disabled(true)
                        } else {
                            Picker("", selection: $model.selectedDeviceIndex) {
                                ForEach(Array(model.availableDevices.enumerated()), id: \.offset) { idx, dev in
                                    Text(model.deviceDisplayTitle(dev)).tag(idx)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 240)
                            .disabled(model.isControlsLocked)
                        }

                        Button {
                            model.refreshDevices()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isControlsLocked)
                        .help("刷新虚拟音频设备")
                        .accessibilityLabel("刷新设备")
                    }
                }

                if model.availableDevices.isEmpty {
                    HStack(alignment: .top, spacing: DS.s8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text("未检测到虚拟麦克风设备。请先运行 Scripts/install-audio-driver.sh 安装 KKvoice Mic，或安装 BlackHole 2ch 后点击刷新。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                }

                CardDivider()

                LabeledRow(
                    "电脑唤醒键",
                    subtitle: "在 Mac 键盘上触发遥控器收音的全局快捷键",
                    systemImage: "command.square"
                ) {
                    HStack(spacing: DS.s8) {
                        Picker("", selection: wakeBinding) {
                            ForEach(Array(model.wakeKeyTitles.enumerated()), id: \.offset) { idx, title in
                                Text(title).tag(idx)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .disabled(model.isControlsLocked)

                        if model.wakeSelectionIndex == InputShortcut.choices.count + 1 {
                            Button("录制…") {
                                model.promptCustomWakeShortcut()
                            }
                            .controlSize(.small)
                            .disabled(model.isControlsLocked)
                            .help("重新录制自定义电脑唤醒键")
                        }
                    }
                }

                CardDivider()

                LabeledRow(
                    "输入软件快捷键",
                    subtitle: "收音就绪后自动发送给语音输入软件（豆包 / 微信 / Typeless / Vokie）",
                    systemImage: "bolt.horizontal.circle"
                ) {
                    HStack(spacing: DS.s8) {
                        Picker("", selection: inputBinding) {
                            ForEach(Array(model.inputKeyTitles.enumerated()), id: \.offset) { idx, title in
                                Text(title).tag(idx)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .disabled(model.isControlsLocked)

                        if model.inputSelectionIndex == InputShortcut.choices.count {
                            Button("录制…") {
                                model.promptCustomInputShortcut()
                            }
                            .controlSize(.small)
                            .disabled(model.isControlsLocked)
                            .help("重新录制自定义输入软件快捷键")
                        }
                    }
                }

                CardDivider()

                LabeledRow(
                    "遥控器语音键",
                    subtitle: "控制按下遥控器 Google 助理键时的收音行为",
                    systemImage: "mic.circle"
                ) {
                    Picker("", selection: voiceModeBinding) {
                        ForEach(Array(AppModel.voiceModeTitles.enumerated()), id: \.offset) { idx, title in
                            Text(title).tag(idx)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(model.isControlsLocked)
                }
            }
        }
    }

    private var footerNote: some View {
        HStack(spacing: DS.s8) {
            Image(systemName: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("测试版：请在输入软件中选择相同的虚拟麦克风和快捷键。录音按一次开始、再按一次结束。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.s4)
    }
}

struct GoogleAssistantDotsView: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: -size * 0.22, y: -size * 0.08)
            Circle()
                .fill(Color(red: 0.92, green: 0.26, blue: 0.21))
                .frame(width: size * 0.28, height: size * 0.28)
                .offset(x: size * 0.16, y: -size * 0.16)
            Circle()
                .fill(Color(red: 0.98, green: 0.74, blue: 0.02))
                .frame(width: size * 0.33, height: size * 0.33)
                .offset(x: size * 0.16, y: size * 0.20)
            Circle()
                .fill(Color(red: 0.20, green: 0.66, blue: 0.33))
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: size * 0.40, y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
