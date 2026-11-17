import RemoteAudio
import SwiftUI
import VoiceSessions

struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @State private var pulseRing = false

    private static let controlColumnWidth: CGFloat = 240
    private static let refreshButtonWidth: CGFloat = 28

    private var remoteHighlightedID: String? {
        if model.isRecording {
            return "voice"
        }
        return model.lastPressedButtonID
    }

    var body: some View {
        PageScaffold(title: "连接") {
            HStack(alignment: .top, spacing: DS.s20) {
                deviceHeroCard
                    .frame(width: 264)

                VStack(alignment: .leading, spacing: DS.s16) {
                    statusCard
                    voiceSettingsCard
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $model.showIMEOnboardingGuide) {
            IMEOnboardingGuideSheet(model: model)
        }
    }

    private var heroStageTone: StatusTone {
        if model.connectionPhase == .standby {
            return .disconnected
        }
        return model.connectionPhase.tone
    }

    private var deviceHeroCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .center, spacing: DS.s16) {
                HStack(spacing: DS.s8) {
                    GoogleAssistantDotsView(size: 14)
                    Text("遥控器")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    heroStageTone.color.opacity(0.11),
                                    DS.subtleFill
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(heroStageTone.color.opacity(0.20), lineWidth: 1)
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
                    .padding(.vertical, 8)
                }
                .frame(height: 212)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear { pulseRing = model.isRecording }
                .onChange(of: model.isRecording) { active in
                    pulseRing = active
                }

                VStack(spacing: 4) {
                    HStack(spacing: DS.s8) {
                        StatusDot(tone: heroStageTone, size: 9)
                        Text(model.connectionPhase.headlineTitle)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                    }
                    if model.isRecording && model.recordingFrames > 0 {
                        Text("已接收 \(model.recordingFrames) 帧")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                    } else if !deviceSubtitleText.isEmpty {
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
                        title: "蓝牙",
                        stateText: bluetoothStepText,
                        tone: bluetoothStepTone
                    )
                    channelStepRow(
                        icon: "dpad.fill",
                        title: "按键",
                        stateText: hidStepText,
                        tone: hidStepTone
                    )
                    channelStepRow(
                        icon: "waveform.badge.mic",
                        title: "语音",
                        stateText: voiceStepText,
                        tone: voiceStepTone
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !model.isSessionActive {
                    Button {
                        model.connect()
                    } label: {
                        HStack(spacing: DS.s8) {
                            Image(systemName: "link")
                            Text("连接")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canConnect)
                    .help(!model.isKKvoiceMicAvailable ? "请先安装 KKvoice Mic" : "连接遥控器")

                    if !model.isKKvoiceMicAvailable {
                        Text("需先安装 KKvoice Mic 才可连接")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } else if model.connectionPhase == .standby {
                    HStack(spacing: DS.s8) {
                        Button {
                            model.scanRemote(duration: 60)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text("搜索遥控器")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .help("开启 60 秒蓝牙扫描窗口")

                        if model.hasEverConnectedRemote {
                            Button {
                                withAnimation(DS.stateAnimation) {
                                    model.showManualPairingGuide.toggle()
                                }
                            } label: {
                                Text("配对说明")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .fixedSize()
                            .help("显示首次蓝牙配对说明")
                        }
                    }
                } else {
                    Button {
                        model.disconnect()
                    } label: {
                        HStack(spacing: DS.s8) {
                            Image(systemName: "xmark.circle")
                            Text("断开")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("断开遥控器")
                }
            }
        }
    }

    private var deviceSubtitleText: String {
        switch model.connectionPhase {
        case .disconnected:
            return ""
        case .connecting:
            return "配对或按键唤醒后将自动连接"
        case .standby:
            return "当前使用其他收音设备 · 按遥控器任意键自动重连"
        case .keysConnected:
            return "正在连接语音"
        case .voiceReady:
            return "按语音键或键盘触发键说话"
        case .recording:
            return "按语音键或键盘触发键结束"
        case .permissionRequired:
            return "授权后重新连接"
        case .error(let msg):
            return msg
        }
    }

    private var bluetoothStepTone: StatusTone {
        if let perm = model.requiredPermission, perm == "bluetooth" {
            return .warning
        }
        if model.voiceChannelReady && model.hidConnected {
            return .connected
        }
        if model.voiceChannelReady || model.hidConnected {
            return .connecting
        }
        if model.connectionPhase == .standby {
            return .disconnected
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
        if model.voiceChannelReady && model.hidConnected {
            return "已连接"
        }
        if model.voiceChannelReady || model.hidConnected {
            return "连接中"
        }
        if model.connectionPhase == .standby {
            return "待机"
        }
        if model.isSessionActive {
            return "等待连接"
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
        if model.connectionPhase == .standby {
            return .disconnected
        }
        if model.isSessionActive {
            return .connecting
        }
        return .disconnected
    }

    private var hidStepText: String {
        if let perm = model.requiredPermission {
            if perm == "input-monitoring" {
                return "需输入监控"
            }
            if perm == "accessibility" {
                return "需辅助功能"
            }
        }
        if model.hidConnected {
            return "已就绪"
        }
        if model.connectionPhase == .standby {
            return "待唤醒"
        }
        if model.isSessionActive {
            return "待唤醒"
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
        if model.connectionPhase == .standby {
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
        if model.connectionPhase == .standby {
            return "其他收音设备"
        }
        if model.isSessionActive {
            return "待连接"
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
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("状态", systemImage: "waveform.path.ecg")

                if let permission = model.activePermissionIssue {
                    permissionBanner(for: permission)
                }

                HStack(alignment: .top, spacing: DS.s12) {
                    statusTile(
                        title: "遥控器",
                        value: model.statusText,
                        icon: "dot.radiowaves.up.forward",
                        tone: model.connectionPhase.tone
                    )
                    statusTile(
                        title: "键盘触发键",
                        value: model.wakeSelectionIndex == 0 ? "未启用" : model.keyboardStatusText,
                        icon: "keyboard",
                        tone: model.wakeSelectionIndex == 0 ? .disconnected : keyboardTone
                    )
                    statusTile(
                        title: "音源",
                        value: model.activeOrStandbySource.isRemote ? "遥控器" : "其他收音设备",
                        icon: model.activeOrStandbySource.isRemote ? "appletvremote.gen4" : "mic.fill",
                        tone: audioSourceTone
                    )
                }

                if model.shouldShowPairingGuide {
                    pairingGuideBar
                }
            }
        }
    }

    private var pairingGuideBar: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("首次配对：同时长按「← + 🏠」3 秒至指示灯闪烁，在系统蓝牙中连接 Chromecast Remote")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 4)

            Button("蓝牙设置") {
                model.openBluetoothSettings()
            }
            .controlSize(.small)
            .fixedSize()
            .help("打开系统蓝牙设置")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                .fill(DS.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    private var audioSourceTone: StatusTone {
        if model.isRecording {
            return .recording
        }
        return .connected
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
                .foregroundStyle(value == "未启用" ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
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

            Button("打开设置") {
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

    private var selectedDeviceSummary: String {
        guard !model.availableDevices.isEmpty else {
            return model.emptyDevicePlaceholderTitle
        }
        let idx = model.availableDevices.indices.contains(model.selectedDeviceIndex) ? model.selectedDeviceIndex : 0
        return model.deviceDisplayTitle(model.availableDevices[idx])
    }

    private var selectedWakeSummary: String {
        let titles = model.wakeKeyTitles
        let idx = titles.indices.contains(model.wakeSelectionIndex) ? model.wakeSelectionIndex : 0
        return titles[idx]
    }

    private var selectedInputSummary: String {
        let titles = model.inputKeyTitles
        let idx = titles.indices.contains(model.inputSelectionIndex) ? model.inputSelectionIndex : 0
        return titles[idx]
    }

    private var voiceSettingsCard: some View {
        Card(padding: DS.s16) {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader("语音设置", systemImage: "slider.horizontal.3") {
                    if model.isControlsLocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("收音中不可修改")
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

                LabeledRow("虚拟麦克风", systemImage: "mic.and.signal.meter") {
                    HStack(spacing: DS.s8) {
                        Menu {
                            ForEach(Array(model.availableDevices.enumerated()), id: \.offset) { idx, dev in
                                Button {
                                    model.selectVirtualDevice(at: idx)
                                } label: {
                                    if idx == model.selectedDeviceIndex {
                                        Label(model.deviceDisplayTitle(dev), systemImage: "checkmark")
                                    } else {
                                        Text(model.deviceDisplayTitle(dev))
                                    }
                                }
                            }
                        } label: {
                            Text(selectedDeviceSummary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuStyle(.borderedButton)
                        .frame(width: Self.controlColumnWidth - DS.s8 - Self.refreshButtonWidth)
                        .disabled(model.isControlsLocked || model.availableDevices.isEmpty)

                        Button {
                            model.refreshDevices()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .frame(width: Self.refreshButtonWidth)
                        .disabled(model.isControlsLocked)
                        .help("刷新设备")
                        .accessibilityLabel("刷新设备")
                    }
                    .frame(width: Self.controlColumnWidth, alignment: .trailing)
                }

                if !model.isKKvoiceMicAvailable {
                    HStack(alignment: .center, spacing: DS.s12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("需要安装 KKvoice Mic")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let err = model.driverInstallError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let msg = model.driverInstallMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: DS.s8)

                        if model.isDriverInstalling {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("安装中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("安装 KKvoice Mic") {
                                model.installDriver(reinstall: false)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(model.isControlsLocked)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                    )
                }

                CardDivider()

                LabeledRow(
                    "其他收音设备",
                    subtitle: "遥控器未就绪时自动使用",
                    systemImage: "mic.badge.plus"
                ) {
                    Menu {
                        Button {
                            model.selectSystemDefaultMacMic()
                        } label: {
                            if model.selectedMacMicUID.isEmpty {
                                Label("系统默认", systemImage: "checkmark")
                            } else {
                                Text("系统默认")
                            }
                        }

                        if !model.availableMacMics.isEmpty {
                            Divider()
                            ForEach(model.availableMacMics, id: \.uid) { mic in
                                Button {
                                    model.selectMacMic(uid: mic.uid)
                                } label: {
                                    if model.selectedMacMicUID == mic.uid {
                                        Label(mic.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(mic.displayName)
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(model.selectedMacMicTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderedButton)
                    .frame(width: Self.controlColumnWidth)
                    .disabled(model.isControlsLocked)
                }

                CardDivider()

                LabeledRow(
                    "语音软件快捷键",
                    subtitle: "需与输入法「免按 / 点按开始结束」快捷键一致",
                    systemImage: "bolt.horizontal.circle"
                ) {
                    Menu {
                        ForEach(Array(model.inputKeyTitles.enumerated()), id: \.offset) { idx, title in
                            Button {
                                model.selectInputKey(at: idx)
                            } label: {
                                if idx == model.inputSelectionIndex {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }
                    } label: {
                        Text(selectedInputSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderedButton)
                    .frame(width: Self.controlColumnWidth)
                    .disabled(model.isControlsLocked)
                }

                CardDivider()

                LabeledRow(
                    "键盘触发键（可选）",
                    subtitle: "用电脑键盘代替遥控器语音键触发收音",
                    systemImage: "command.square"
                ) {
                    Menu {
                        ForEach(Array(model.wakeKeyTitles.enumerated()), id: \.offset) { idx, title in
                            Button {
                                model.selectWakeKey(at: idx)
                            } label: {
                                if idx == model.wakeSelectionIndex {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }
                    } label: {
                        Text(selectedWakeSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderedButton)
                    .frame(width: Self.controlColumnWidth)
                    .disabled(model.isControlsLocked)
                }

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    Text("请在输入法中将麦克风选为「KKvoice Mic」（停用或卸载后改回「系统默认」），并开启「免按 / 启动语音输入」模式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Button("引导说明") {
                        model.showIMEOnboardingGuide = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                        .fill(DS.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                        .strokeBorder(DS.border, lineWidth: 1)
                )
            }
        }
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

private struct IMEOnboardingGuideSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("语音输入法设置引导")
                        .font(.title3.bold())
                    Text("首次使用请按以下两步检查你常用的语音输入法设置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                guideSection(
                    step: "1",
                    title: "将输入法麦克风设为「KKvoice Mic」",
                    detail: "在豆包输入法 / 微信输入法 / Vokie 的设置中，将麦克风设备选择为「KKvoice Mic」。若日后停用或卸载 KKvoice，请手动改回「系统默认」。"
                )

                guideSection(
                    step: "2",
                    title: "开启各输入法的「免按 / 免提」模式",
                    detail: "只需在输入法中开启下方模式，KKvoice 会自动让遥控器同时支持「短按一下切换」与「按住说话、松开结束」两种按法："
                )

                VStack(alignment: .leading, spacing: 8) {
                    appRuleRow(
                        app: "豆包输入法",
                        rule: "语音输入 → 点击设置「免按模式」，「全局唤起语音」设置为「持续模式」。"
                    )
                    appRuleRow(
                        app: "微信输入法",
                        rule: "语音输入 → 快捷键 → 选「启动语音输入」，关闭「按住说话」，启用「快捷键全局生效」。"
                    )
                    appRuleRow(
                        app: "Vokie",
                        rule: "设置 → 通用 → 修改快捷键 → 打开「免提」模式。"
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.border, lineWidth: 1)
                )

                guideSection(
                    step: "3",
                    title: "核对触发快捷键",
                    detail: "确保 KKvoice「连接」页中的「语音软件快捷键」与你在输入法内设置的快捷键一致（默认均为 Fn）。"
                )
            }

            HStack {
                Text("后续可随时在「连接」页右下角点击「引导说明」再次查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("我知道了") {
                    model.dismissIMEOnboardingGuide()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 520)
    }

    private func guideSection(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appRuleRow(app: String, rule: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("• \(app)：")
                .font(.footnote.weight(.semibold))
                .frame(width: 82, alignment: .leading)
            Text(rule)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
