# KKvoice 技术难点与实现笔记

本文档专门记录 KKvoice 在开发与适配 macOS 语音输入生态过程中遇到的几个核心技术问题及其底层解决方案。如果你只是日常使用 KKvoice，直接阅读主页 [README.md](../README.md) 即可。

---

## 1. 为什么输入法只开启“单击免按模式”，遥控器却能同时实现“短按切换”与“长按说话”？

主流语音输入法（如豆包输入法、微信输入法、Vokie）通常提供两种录音模式：
- **免按/单击模式（Toggle）**：按一下快捷键开始录音，再按一下结束；
- **长按模式（Push-to-Talk）**：按住快捷键说话，松开结束。

但在遥控器硬件上，用户既希望能“按一下放开连续说一段长话”，又希望能“按住说一句短话松手即停”。如果让用户在软件里来回切换模式会非常繁琐。

### 实现原理（双模状态机 `VoiceSession`）
KKvoice 内部将语音软件统一视为**「按一下开始，再按一下结束」的切换式目标**，并由独立的状态机 `VoiceSession`（`.hybrid` 混合模式）接管遥控器语音键的按下（`press`）与松开（`release`）时序：

1. **按下遥控器语音键（`t = 0s`）**：
   - KKvoice 立即向遥控器发送开麦指令（`AUDIO_OPEN`）并开启虚拟声卡 `KKvoice Mic`；
   - 收音流就绪后，KKvoice 向系统注入**第 1 次**快捷键脉冲（按下 + 释放），触发语音输入法**开始录音**。
2. **情况 A：用户短按（`< 0.5s` 内松开语音键）**：
   - `VoiceSession` 判定本次按键时长 `< 0.5s`，在松开时**不发送任何停止信号**，保持收音会话处于 `.recording` 状态；
   - 当用户说完话、**第 2 次**按下并松开语音键时，`VoiceSession` 关闭遥控器收音并向系统注入**第 2 次**快捷键脉冲，触发语音输入法**结束录音并上屏**。
3. **情况 B：用户长按（按住说话 `≥ 0.5s` 后松开语音键）**：
   - `VoiceSession` 检测到从按下到松开的持续时间 `≥ 0.5s`，在用户松开手指的瞬间直接触发收音结束流程，并注入**第 2 次**快捷键脉冲通知语音输入法**结束录音**。

对于语音输入法而言，无论你是“短按两次”还是“长按一次松手”，它收到的永远是标准的「开始脉冲 $\rightarrow$ 音频流 $\rightarrow$ 结束脉冲」，因此**用户只需在输入法中开启「免按/点按开始结束」模式，即可在遥控器上同时获得短按与长按两种体验**。

更重要的是，这种设计避免了在说话期间向 macOS 系统长时间按死修饰键（如 `Control` 或 `Option`）带来的副作用——如果长按修饰键不放，说话期间点击鼠标左键会变成右键菜单、滚轮会变成缩放，且容易触发输入法的防误触取消机制。

---

## 2. 豆包输入法与微信输入法的底层兼容细节

### 2.1 为什么豆包输入法默认找不到普通虚拟声卡？

许多 macOS 语音工具使用标准的 CoreAudio 虚拟声卡（如原版 BlackHole），但在**豆包输入法**的麦克风下拉列表中却完全看不到该设备，或者选中后录不到声音。

### 根因分析
1. **传输类型过滤**：豆包输入法内部基于 `AVCaptureDevice` 枚举音频输入设备，并在筛选逻辑中排除了传输类型为 `kAudioDeviceTransportTypeVirtual`（虚拟音频设备）的声卡，只保留内置设备（`BuiltIn`）或外接硬件设备（如 `USB`、`Bluetooth`）。
2. **音频流静音与增益状态**：部分输入法或系统音频服务在切换设备时可能将虚拟声卡的主通道置于静音（Mute）或极低增益状态。

### 解决方案
1. **驱动层 USB 传输类型标识**：
   - KKvoice 内置的 `KKvoiceMic.driver` 基于开源 [BlackHole v0.6.1](https://github.com/ExistentialAudio/BlackHole)（GPLv3）源码编译；
   - 在编译脚本 `Driver/build-blackhole-driver.sh` 中，将 `kAudioDevicePropertyTransportType` 的返回值从 `kAudioDeviceTransportTypeVirtual` 修改为 **`kAudioDeviceTransportTypeUSB`（`'usb '`）**，使基于 `AVCaptureDevice` 的输入法将其识别为标准外接 USB 麦克风并正常列出。
2. **会话启动自动解静音与满幅音量**：
   - 每次开始收音时，`KKCoreAudioOutput`（`ensureUnmutedFullVolume`）会自动检查并解除 `KKvoice Mic` 输入/输出端的主通道与分通道静音，同时将音量标量重置为 `1.0`（100%）。

### 2.2 为什么微信输入法对模拟修饰键更挑剔（IOKit 左右侧硬件位校验）？
当用户将快捷键设为 `左 Control`（`0x3B`）、`右 Control`（`0x3E`）或 `左/右 Option` 等修饰键时：
- **豆包输入法**主要检查 `CGEventFlags` 的通用修饰键掩码（如 `.maskControl = 0x40000`）；
- **微信输入法（`WeType`）** 的 `ShortcutKeyMonitor.handleFlagsChanged` 则直接按 `keyCode` 校验底层 IOKit 的**设备侧专属标志位（Device-dependent side flags）**：
  - `LeftControl (0x3B)`：`0x0001`（`NX_DEVICELCTLKEYMASK`）
  - `RightControl (0x3E)`：`0x2000`（`NX_DEVICERCTLKEYMASK`）
  - `LeftShift (0x38)` / `RightShift (0x3C)`：`0x0002` / `0x0004`
  - `LeftCommand (0x37)` / `RightCommand (0x36)`：`0x0008` / `0x0010`
  - `LeftOption (0x3A)` / `RightOption (0x3D)`：`0x0020` / `0x0040`
- 如果合成的 `kCGEventFlagsChanged` 事件仅设置了通用位 `0x40000` 而未携带 `0x0001`，微信输入法会判定 `flags & 0x0001 == 0`，把“按下”事件误判为“释放”事件而完全忽略。
- 因此，`SystemShortcut` 与 `ShortcutDefinition` 在构造修饰键事件时，同时写入了通用掩码与对应的 IOKit 硬件侧标志位（如 `LeftControl = 0x40001`），使其与真实物理键盘产生的中断事件完全一致。

---

## 3. 当「键盘触发键」与输入法快捷键设为同一个键时，如何防止被输入法抢走？

许多用户习惯将语音输入法的快捷键设为 `Fn` 或 `左 Control`，同时希望在遥控器不在手边时，直接按电脑键盘上的**同一个键**也能由 KKvoice 唤醒收音（自动切换遥控器麦克风或电脑备用麦克风）。

如果未做特殊处理，按下键盘上的 `Fn` 或 `左 Control` 时，豆包输入法或微信输入法会直接拦截并吞掉该按键、立刻启动录音，而 KKvoice 根本收不到按键信号，导致遥控器无法被唤醒。

### 根因分析
1. **macOS 事件拦截层级（`CGEventTapLocation`）**：
   - macOS WindowServer 的全局事件拦截分为 `kCGHIDEventTap`（底层 HID 硬件层，优先级最高）与 `kCGSessionEventTap`（用户会话层，优先级较低）；
   - 豆包输入法与微信输入法均在 **`kCGHIDEventTap`** 创建阻塞式事件监听（`kCGEventTapOptionDefault`）。如果 KKvoice 挂载在 `kCGSessionEventTap`，按键事件在到达 KKvoice 之前就会被输入法在 HID 层消费并返回 `NULL`。
2. **同层级后进先出顺序（LIFO）**：
   - 在同一个 `kCGHIDEventTap` 层级内，macOS 默认让**最后创建的 `kCGHeadInsertEventTap` 监听排在最前面**。如果用户在输入法设置里刚刚修改过快捷键，输入法重建的监听就会排到 KKvoice 前面。

### 解决方案（HID 层按需挂载 + 显式注销端口 + 合成事件染色放行）
1. **挂载至 `kCGHIDEventTap` 头部**：
   - 当用户启用「键盘触发键」或进入收音/切换器会话时，`KKvoiceRemoteHelper` 在 `kCGHIDEventTap`（`kCGHeadInsertEventTap`）创建全局键盘监听；若「键盘触发键」设为「不启用」且处于空闲状态，则保持 **0 个**键盘监听钩子。
2. **严禁定时轮询抢占 + 销毁时必须调用 `CFMachPortInvalidate`**：
   - **踩坑教训**：微信输入法（`WeType`）后台自带定时器检测并重建其 `kCGHIDEventTap`。若 `KKvoiceRemoteHelper` 也使用定时器轮询 `CGGetEventTapList` 抢占 `#0` 首位，双方会陷入每 1.5 秒一次的无限互抢重建循环；更严重的是，`CGEventTapCreate` 返回的 `CFMachPortRef` 若仅调用 `CGEventTapEnable(tap, false)` 和 `CFRelease(tap)` 而不调用 **`CFMachPortInvalidate(tap)`**，底层 Mach 端口会永久残留在 macOS `WindowServer` 全局事件表中（每小时泄漏约 2,400 个僵尸 tap），导致整机鼠标移动与键盘输入严重卡顿。
   - **修复方案**：移除周期性轮询定时器，仅在配置变更或用户从豆包输入法设置窗口切出（`NSWorkspaceDidDeactivateApplicationNotification`）时按需重建一次；且每次释放 `eventTap` 前必须先执行 `CFMachPortInvalidate(self.eventTap)`，确保 `WindowServer` 立即注销对应端口。
3. **物理按键拦截与合成事件染色放行**：
   - 当用户按下物理键盘触发键时，排在 `#0` 的 `KKvoiceRemoteHelper` 优先拦截并返回 `NULL`（吞掉物理按键，阻止输入法提前抢跑），同时通知 KKvoice 主进程唤醒遥控器麦克风（或开启备用收音设备）；
   - 待音频通道准备就绪且物理按键释放后，KKvoice 通过 `SystemShortcutSender` 发送带有专属 `kCGEventSourceUserData` 标记（`kKKvoiceSyntheticKeyMarker = 0x4B4B564F494345`）的合成按键事件；
   - 排在 `#0` 的 `KKvoiceRemoteHelper` 识别到该内部标记后直接放行（`return event`），将合成按键原样传递给排在后面的语音输入法启动录音。

---

## 4. 为什么不能在遥控器未完成系统配对时直接发起 BLE 连接？

Google TV / Chromecast 语音遥控器使用双通道通信：
- 普通按键与唤醒走系统标准的 **Bluetooth HID**；
- 语音音频流走自定义的 **ATVV BLE GATT 服务**（`AB5E0001-5A21-4F05-BC7D-AF01F617B664`）。

### 踩坑现象
如果遥控器刚刚进入配对模式（脉冲闪灯），尚处于 macOS「系统设置 → 蓝牙」的「附近设备」列表中等待用户点击连接，此时若应用后台正在调用 `CBCentralManager` 扫描并直接发起 `connectPeripheral:`，会建立一条未加密绑定（Unbonded）的 BLE 连接，直接占满遥控器唯一的 BLE 连接槽位，导致 macOS 系统蓝牙配对一直转圈失败、无法挂载 HID 键盘设备。

### 解决方案（系统 HID 挂载门禁）
- `KKvoiceRemoteHelper` 通过 `IOHIDManagerCopyDevices` 实时检查系统是否已挂载遥控器的 `IOHIDDevice`（`VendorID = 0x18D1, ProductID = 0x9450`）；
- **只有当系统蓝牙已完成配对并挂载 HID 设备后**，才允许 `CBCentralManager` 连接该遥控器的 BLE ATVV 语音服务；若检测到设备尚未挂载 HID，则主动释放连接让位给 macOS 系统完成配对。

---

## 5. 待机零采集与外出零功耗待机

1. **待机零麦克风采集**：
   - 平时待机状态下，KKvoice **绝不开启任何物理麦克风或遥控器麦克风**，也不会触发 macOS 菜单栏的橙色麦克风指示点；
   - 仅在用户按下遥控器语音键或键盘触发键进入收音会话时，才按需打开遥控器音频流或备用收音设备；收音结束或取消时立即停止采集并清零音频缓冲区。
2. **外出零功耗蓝牙待机**：
   - 当携带 MacBook 外出（遥控器不在身边）时，`KKvoiceRemoteHelper` 在短暂重连窗口结束后会自动停止所有 `CBCentralManager` 蓝牙扫描与轮询定时器，进入**零功耗被动待机（`remote_standby`）**；
   - 当回到遥控器旁按下遥控器任意键时，macOS 内核蓝牙栈会自动重连 HID 设备并触发 `IOHIDManager` 匹配回调，瞬间唤醒语音通道重连。
