# KKvoice 接入闪念笔记

历史集成设计说明（部分内容已过时）。SnapNote 模块目前已接入 App；具体实现以 `Sources/KKvoice/KKvoiceApp.swift`、`SnapNote/` 和 `SnapNoteTests/` 为准。下方协议说明仍可作为安全边界与原始设计背景，不应视作当前状态描述。

## 安全要求

- Token 只能由用户显式输入，使用 `SnapNoteTokenStore.save` 写入本机 Keychain；`load` 返回可选值，未配置时提示用户。删除设置时可调用 `delete`。Keychain 操作可能弹出系统授权或阻塞，避免放在实时音频线程。不得把值写进普通配置、发给 helper、记录到日志或错误提示，也不得读取其他应用的私有配置。
- 客户端只连接 `http://127.0.0.1:31090/snapnote/data-source/mcp`，拒绝重定向；当前地址和标签固定。请求仍会向监听该端口的本机进程发送令牌，本地 HTTP 没有服务端加密认证。
- 用户必须自行配置并启用闪念笔记「应用外新建笔记」快捷键；本功能不设置默认组合键。快捷键形如 `shortcut:command+option:N`。不要在录音期间执行。原生快捷键发出后等待 0.5 秒，再输入英文句点 `.`，不按回车；成功后句点保留，用户再按原有语音键。

## 模块和回调

1. 为 Swift Package 新增指向 `SnapNote` 目录的模块，并将其列为 App 依赖。使用 `SnapNoteTokenStore().load()`，令牌存在时创建 `try SnapNoteMCPClient(token: token)`；不要打印对象或令牌。
2. 一个辅助进程连接对应一个 `SnapNoteHelperActionAdapter`。`send` 闭包应将 `SnapNoteHelperMessage.wireFields` 写入同一条**串行、非阻塞且能抛错**的 helper 通道。开始消息字段为 `type=post_key`、`target=snapnoteNewNote`、`actionId`、`shortcut`；取消为 `type=cancel_snapnote_action`、`actionId`。不能使用无回执的异步派发冒充已写入，否则启动与取消的顺序可能颠倒；写入失败意味着是否送达未知。
3. helper 的 `action_done`、`action_error` 和 `snapnote_action_cancelled` 按其 `actionId` 转为 UUID 后，通过 `await adapter.handleHelperEvent(type:actionID:prevented:)` 交给当前连接对应的适配器。丢弃旧连接事件；不得传入用户笔记正文或原始错误消息。
4. **当前 helper 未实现取消协议**。适配器默认 `cancellationAcknowledgementSupported: false`，此时不会发送新建动作。只有当前运行的 helper 确认实现下面的约定，并经实际进程测试后，才可传 `true`：`cancel_snapnote_action` 在与延迟句点相同的串行队列上按 actionId 原子取消；只有保证将来不会发出快捷键或句点时，才能回 `snapnote_action_cancelled`、相同 `actionId`、`prevented=true`。已完成或状态不确定必须回 `prevented=false`；旧 ID 不得取消新动作。
5. helper 退出、连接异常、主动 shutdown 或进程替换，均调用 `await adapter.helperDisconnected()`，无论是否有待处理动作；连接重建后才创建新的适配器。取消无确认或 helper 断开将使旧适配器隔离，不得直接恢复或重试。已存在的 helper `shutdown` 消息不构成取消确认。
6. `SnapNoteCoordinator(client:native:isRecording:)` 的录音检查闭包必须线程安全且及时反映开始中的录音；App 应串行协调录音开始和闪念动作，防止检查后新录音并发启动。以单一 coordinator 实例调用 `await createAndTag(shortcut:)`；配置变化时取消当前任务、等待 helper 取消结果，再替换客户端和适配器。
7. 显示 `SnapNoteOutcome` 的安全状态：只有 `succeeded` 为真才报告标签已确认；`noteMayExist` 代表可能已发出新建动作，`tagMayHaveBeenWritten` 代表写请求可能产生副作用。超时、断连、取消或结果未知时提示用户检查闪念笔记，**不要自动重试新建或标签写入**。不要在 UI 或日志中输出 UUID、正文、Token、HTTP 请求／响应或原始异常。

默认总时限 22 秒；helper 自身默认等待 8 秒、取消确认再等待 1 秒。总时限在依赖遵守 Swift 任务取消的情况下生效；失败后仍需等待辅助程序取消确认或隔离，故清理可能多耗时。测试可运行 `SnapNoteTests/run.sh`。

## 必须保留的边界

当前实现只确认应用位于前台，不能证明新建成功或正文已聚焦。若旧笔记仍有焦点，句点可能进入旧正文；后续唯一 UUID 与正文检查只阻止错误加标签，不能撤销句点。前后快照只覆盖最近 100 条笔记；并发创建、草稿复用、快速输入、服务异常会失败退出。禁止通过猜测“最近一条”兜底。

正式启用前应验证：helper 取消/超时/断线、配置改变时无迟到句点；遥控器动作唯一 UUID 和标签回读；前台/焦点失败；录音与新建互斥；不同语音软件输入；Keychain 锁定与拒绝授权。不要用真实 Token、笔记内容或 UUID 作为测试日志。
