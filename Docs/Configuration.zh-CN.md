# DramaPlayer 参数与调试参考

本文对应当前源码中的开发版本。生产接入请以所固定的提交或正式发行标签验证接口。Swift Package Manager 使用 `ReelsPlaybackCore` 和 `ReelsPlaybackUIKit`，CocoaPods 使用 `import DramaPlayer`。

## 会话与播放策略

```swift
let session = PlaybackSession(
    configuration: .init(
        mode: .vertical,
        autoplay: true,
        preload: .preparedPlayer,
        endBehavior: .advance,
        preparedItemLimit: 3,
        retention: 120,
        rates: [0.75, 1, 1.25, 1.5, 2],
        streamPreferences: .init(),
        loadTimeout: 20
    ),
    sourceProvider: resolver,
    cache: mediaCache,
    logger: logger
)
```

`resolver`、`mediaCache` 与 `logger` 由宿主提供。存储和授权策略由业务控制。

| 参数 | 默认值 | 生效范围与边界 |
| --- | --- | --- |
| `mode` | `.single` | 单视频模式只持有 1 个播放器槽位。`.vertical` 开启邻集与最近访问剧集的复用窗口。UIKit 布局由宿主选择对应视图。 |
| `autoplay` | `true` | 选集时设置播放意图。会话激活、无暂停原因且已获授权时才播放。用户手动暂停过的剧集在当前队列中保持暂停意图。 |
| `preload` | `.preparedPlayer` | `.disabled` 关闭主动预加载，`.preparedPlayer` 预备相邻槽位，`.mediaBytes` 请求宿主预取下一集。用 `setPreloadPolicy(_:)` 修改当前策略，释放非当前播放器并取消旧预取。 |
| `setMediaPrefetchPolicy(_:)` | `nil` | 仅用于 `.mediaBytes`。传入相对集数或按剧集 ID 排序的选择函数，默认最多 3 个有效候选，可配置为 0–8。SDK 按顺序校验权限并逐个预取；修改时保留当前集和已写入的缓存。传 `nil` 恢复仅预取下一集。 |
| `endBehavior` | `.stop` | `.loop` 从头重播，`.advance` 转到下一集并在末集停止。`.ended(id)` 在循环或切集前发出。 |
| `preparedItemLimit` | `3` | 限制在 1–3，包含当前集。单视频模式固定使用 1 个槽位。此参数限制播放器数量，磁盘配额由缓存实现负责。 |
| `retention` | `120` 秒 | 播放器复用的最长停留时间，在切集、预加载窗口更新等时机检查。使用单调时钟，签名 URL 到期仍以实际日期判断。设为 0 可使已停放的播放器很快失去复用资格。 |
| `rates` | `[0.5, 0.75, 1, 1.25, 1.5, 2]` | 过滤无效值、去重、排序并保留 `1`。通过 `setRate(_:)` 选择列表中的值。 |
| `streamPreferences` | 三个值均为 `0` | `preferredPeakBitRate` 和 `preferredPeakBitRateForExpensiveNetworks` 单位是 bit/s，`preferredForwardBufferDuration` 单位是秒。0 交由 AVFoundation。通过 `setStreamPreferences(_:)` 同步修改已保留和后续播放器。 |
| `loadTimeout` | `nil` | 默认关闭，Demo 显式设为 30 秒。单次加载预算覆盖源解析、缓存查询、播放器就绪和初始定位。有限值限制在 0.1–300 秒。适用缓存回源时会开始一次新的加载预算。已就绪后的卡顿通过诊断事件上报。 |
| `sourceProvider` | 必传 | `.playback` 和 `.preload` 都必须校验同一播放权限。预加载授权的播放器可能直接复用。预加载分支应尊重任务取消，并避免发起购买等业务操作。 |
| `cache` | `DirectPlaybackMediaCache()` | 直接使用源 URL。宿主缓存应只在确认完整、可读时返回 `isCached: true`。缓存文件失败时尝试回源一次。 |
| `focus` | `PlaybackFocus.shared` | 同一焦点域内只让一个会话主动播放。列表、大窗和小窗应使用同一个会话移动展示层。 |
| `logger` | `nil` | 默认关闭 SDK 打印。只对当前会话生效，可设置日志级别并路由到宿主日志系统。 |

`PlaybackItem.id` 用稳定、唯一的业务 ID。空 ID 与重复 ID 会在 `setItems` 中过滤。传入 `resumePosition` 时使用秒，SDK 会按可用时长约束初始位置。生产环境不要用签名 URL 作为 ID 或缓存键。缓存键按账户、资产版本和码率档位隔离。账号切换时同步处理宿主缓存与 `invalidateSources()`。更完整的接线示例见 [Integration guide](Usage.md)。

## 画面、模板和小窗

| 参数或接口 | 用法 |
| --- | --- |
| `scaling` | UIKit 播放视图仍默认 `.fill`。单视频需要完整画面时传入 `.fit`。可在窗口尺寸变化时修改，封面和视频使用相同的策略。 |
| `showsControls` | 内置播放器视图默认显示控制栏。可以隐藏内置栏，使用快进、倍速、拖动与事件接口构建宿主的控件。 |
| `isLandscapeAdjustmentEnabled` | UIKit 播放视图默认关闭。启用后在横向窗口的横向播放区上下滑，左侧调当前屏幕亮度，右侧调会话播放音量。进度条等原生控件保持独立。竖滑列表中间 20% 留给翻页。 |
| `setVolume(_:)` | 会话音量默认 `1`，有限值限制在 `0...1`，切集和预加载播放器复用时继续生效。它调整相对于系统音量的播放器增益。 [Apple AVPlayer 音量说明](https://developer.apple.com/documentation/avfoundation/avplayer/volume) |
| `coverLoader` | 默认从本地或 HTTP(S) URL 加载图片。对大量系统剧集封面，注入宿主的图片缓存与解码流程。 |
| `coverState` / `onCoverStateChange` | `PlaybackVideoView` 和 `SinglePlaybackView` 提供封面状态及回调，独立于视频状态。缺失和失败用占位图。首帧到达时会取消仍在进行的封面请求。 |
| `retryCoverLoading()` | 封面仍可见且上次加载失败时单独重试封面，视频会话和进度继续保留。 |
| `PlaybackLayoutTemplate.presets` | 6 个比例乘以 Fit 和 Fill，共 12 套。通过 `fittedSize(in:)` 获取容器尺寸；设置播放器的 `scaling` 后，视图会按对应方式呈现。 |
| `PlaybackMiniPlayerView.preferredSize` | 默认 240 × 180 pt，包含标题拖动区。用 `setPreferredSize(_:)` 传入正且有限的宽高。可见尺寸受可用空间约束，正常空间下最小 152 × 112 pt。 |
| `layout(in:)` | 每次宿主重新布局时传入父视图坐标系中的安全区和留白范围。将现有播放器视图移入 `contentView`，展开时移回原容器，保留会话与进度。 |

小窗是应用内浮层。宿主决定其显示空间、导航范围与关闭时机。折叠、展开或分屏使用当下视图尺寸重新计算安全区。iPhone Duo 双屏全幅与多姿态需要在目标 SDK 实测。 [Apple iPhone Duo 适配指南](https://developer.apple.com/iphone-duo/prepare/)

## 调试打印和线上诊断

调试期注入统一日志，生产期按需要配置更高阈值或关闭。

```swift
#if DEBUG
let logger: PlaybackLogger? = .system(subsystem: "com.example.shortdrama", minimumLevel: .debug)
#else
let logger: PlaybackLogger? = nil
#endif
```

- **Demo 开关**：在 Xcode 的 **Edit Scheme → Run → Arguments** 勾选 `-DramaPlayerDebugLogging YES`，运行 Debug 构建。在控制台按子系统 `com.amiaocat.DramaPlayerDemo` 筛选。
- **级别**：`.debug` 查看会话、源请求、媒体命中、预取与流媒体配置；`.info` 查看首帧、播放尝试和主动切换；`.warning` 查看卡顿、加载超时、缓存回源和预取失败；`.error` 查看当前集失败。
- **自定义路由**：`PlaybackLogger(minimumLevel:includesItemIdentifiers:sink:)` 把结构化条目交给宿主。回调同步执行，批量写盘、网络上报等重操作由宿主移出回调。默认关闭剧集 ID，系统日志会标记已启用的 ID 为私有。SDK 不写源地址、签名 URL、缓存键、原始错误消息或播放进度每一帧。
- **定位一次卡顿**：先按 `sessionID` 筛选，再用 `attemptID` 关联 `attemptStarted`、`firstFrame`、`rebufferingEnded` 和 `attemptFinished`。`prefetchFinished` 表示缓存的预取方法返回，真正的媒体命中以 `mediaResolved` 的 `cacheHit=true` 为准。
- **区分故障**：`loadTimedOut` 之后查 `playbackFailed` 中的 `reason`。先排查 resolver、缓存查询或媒体上线状态，再用 `retry()`。日志适合定位链路，QoE 上报使用独立的 `session.diagnostics()` 事件流。

## 发版验证

```sh
swift test
xcodebuild -project Demo/DramaPlayerDemo.xcodeproj -scheme DramaPlayerDemo \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

用本地 Demo 复现授权重试、复用和回源策略、横竖版、模板与小窗。用目标真机和业务 CDN 验证网络劣化、音画同步、长时间快速翻页和 iPhone Duo 内外屏。为候选版本保存首帧、卡顿、加载失败、内存和预取流量数据，再与线上基线比较。发布矩阵见 [短剧播放生产指南](Production.zh-CN.md)。
