# DramaPlayer 中文接入指南

DramaPlayer 面向 iOS 16+ 的 UIKit 项目，提供单视频播放和竖滑剧集列表。使用 Xcode 15+ 和 Swift 5.9+。如果要自己实现播放界面，可以从 `ReelsPlaybackCore` 开始。

## 安装

下面的安装示例固定在正式标签 `0.1.1`。测试 `main` 的新功能时，可在测试 App 中添加本地源码或固定已审查的提交。原来的模块导入、会话创建及生命周期入口仍然适用。完整画面模式、加载时限和日志通过新增参数启用。

- **Swift Package Manager**：在 Xcode 的 **File → Add Package Dependencies** 中输入 `https://github.com/AmiaoCat/DramaPlayer.git`，选择从 `0.1.1` 开始的版本。使用内置视图时，为 App target 添加 `ReelsPlaybackCore` 和 `ReelsPlaybackUIKit`，并在 Swift 文件中导入这两个模块。
- **CocoaPods**：在 App target 的 Podfile 中加入 `pod 'DramaPlayer', :git => 'https://github.com/AmiaoCat/DramaPlayer.git', :tag => '0.1.1'`。执行 `pod install` 后打开 `.xcworkspace`，在代码中使用 `import DramaPlayer`。只需要 Core 时，使用 `DramaPlayer/Core`。

## 播放第一个视频

1. 复制 [README 的 PlayerViewController](../README.md#quick-start)。控制器会持有一个 `PlaybackSession` 和一个处理应用前后台、音频中断等通知的 `PlaybackLifecycle`。
2. 把 MP4 加到 App target 的资源中，用下面的代码打开播放器。也可以把自己的 HTTPS MP4 或 HLS 播放地址传给 `PlayerViewController`。

   ```swift
   // 在已嵌入 UINavigationController 的页面中调用。
   guard let url = Bundle.main.url(forResource: "episode-01", withExtension: "mp4") else {
       return // 在实际页面上提示媒体资源缺失。
   }
   let player = PlayerViewController(videoURL: url)
   navigationController?.pushViewController(player, animated: true)
   ```

3. 在 `viewDidAppear` 调用 `session.activate()`，在 `viewWillDisappear` 调用 `session.deactivate()`。页面离开时会让出共享播放焦点。业务浮层需要暂停时，成对调用 `setSuspended(_:reason:)`，并使用同一个原因。
4. 接入多集时，为每集使用稳定且唯一的剧集 ID，通过 `setItems(_:selectedID:)` 设置顺序与初始集数。用 `PlaybackSourceResolver` 按 ID 获取实际播放地址，再用 `VerticalPlaybackView` 显示列表。目录跳转调用 `session.select(id)`。

## 运行示例

用 Xcode 打开 [DramaPlayerDemo.xcodeproj](../Demo/DramaPlayerDemo.xcodeproj)，运行 **DramaPlayerDemo** scheme。除远程试播外，其余场景都可用工程内置素材离线体验。示例代码见 [播放控制器](../Demo/Sources/DemoPlayerViewController.swift)和[缓存策略页](../Demo/Sources/DemoCacheViewController.swift)。

| 场景 | 操作与预期结果 | 对应接口 |
| --- | --- | --- |
| Drama collection | 首页打开 12 集短剧流。上下滑或用 **Episodes** 选集，播完自动连播。重新进入会恢复上次集数和进度。片段是开放影片的竖屏改编，支持离线播放。 | `VerticalPlaybackView`、`select(_:)`、`resumePosition` · [素材署名](../Demo/Media/Series/ATTRIBUTION.md) |
| Single video | 点击视频暂停，拖动进度条或切换倍速。片段播完后循环。 | `SinglePlaybackView`、`.loop` |
| Cover loading | 从 **Cases** 切换封面慢、失败、缺失或首帧先到的情况，观察占位和封面状态。 | `PlaybackCoverState`、`onCoverStateChange` |
| Landscape video | 横屏自动全屏，默认完整显示画面，可切换为裁切填满。点右上方的眼睛图标进入沉浸模式，只显示播放进度。轻点画面恢复控件。左右两侧上下滑可调亮度和音量。 | `scaling`、`showsProgressOnly`、`onVideoTap`、`isLandscapeAdjustmentEnabled` |
| Video layouts | 横版和竖版样片可切换 12 套布局。打开 **Mini player** 后拖动顶部或右下角，也可在 **Custom size** 分别输入宽和高。 | `PlaybackLayoutTemplate.presets`、`PlaybackMiniPlayerView` |
| Vertical feed | 上下滑动或点击 **Episodes** 跳集。播完自动进入下一集，末集播完停止。 | `VerticalPlaybackView`、`select(_:)`、`.preparedPlayer`、`.advance` |
| Custom controls | 按 **Play** 从第 2 秒开始，按 **+5 seconds** 快进，播完按 **Replay**。 | `PlaybackVideoView`、`resumePosition`、`events()`、`seek(to:)` |
| Episode access | 第 2 集显示 **Access required**。按 **Unlock episode** 后播放。返回菜单重新进入可再次体验锁定状态。 | `.requiresUserAction`、`retry()` |
| Cache policies | 选 **Custom**，分别设置前后预取 0–2 集。等目标集显示 **Prefetched** 后选中它，查看 **Cache hit**。按 **Clear cache** 从源文件播放当前集并关闭预取。 | `PlaybackMediaPrefetchPolicy`、`PlaybackCacheAdapter` |
| Remote playback | 输入直连 HTTPS 地址，或选择 **Tears of Steel (HLS)**、**Sintel Trailer (MP4)**。打开 MP4 后用 **Download video** 保存供离线播放，点击 **Delete local copy** 删除本地副本。 | `diagnostics()`、`PlaybackDownloadStore` |

## 接入业务数据

### 横屏全屏与沉浸播放

由宿主启用横屏，在横屏布局中将现有播放器约束到容器的四边。播放器内置控制条会避开安全区。保留同一个 `PlaybackSession` 和播放器视图，横竖屏切换时只更新布局和 `scaling`。用 `.fit` 完整显示画面，或用 `.fill` 裁切填满。

```swift
player.showsProgressOnly = true
player.onVideoTap = { [weak player] in
    player?.showsProgressOnly = false
    player?.onVideoTap = nil
}
```

这段写法适用于启用了内置控件的 `SinglePlaybackView` 和 `VerticalPlaybackView`。自定义界面可以直接使用 `PlaybackControlsView.showsProgressOnly`。

### HTTPS MP4 下载

给 `PlaybackDownloadStore` 传入当前账号专用的 Application Support 子目录，并作为 `PlaybackSession` 的 `cache` 参数。播放和下载复用同一个已经通过业务鉴权的 `PlaybackSource`。为 `cacheKey` 使用包含剧集 ID、清晰度和内容版本的稳定标识，便于签名 URL 刷新后复用本地视频。

```swift
let downloads = PlaybackDownloadStore(directory: accountDownloadsDirectory)
let session = PlaybackSession(sourceProvider: sourceProvider, cache: downloads)

try await downloads.download(authorizedMP4Source)
let localURL = await downloads.localURL(for: authorizedMP4Source)
try await downloads.deleteDownload(for: authorizedMP4Source)
```

播放会优先使用已完成的本地副本。下载或删除后需要立即切换来源时，可调用 `session.retry()` 重新加载当前剧集。下载适用于可直接访问的 HTTPS MP4，HLS 示例保留在线播放。账号切换、内容过期和离线授权由宿主应用管理。

- **进度和完播**：通过 `session.events()` 读取 `.snapshot` 和 `.ended(id)`。进度单位是秒。按剧集 ID 保存退出时的进度，下次构建 `PlaybackItem` 时传入 `resumePosition`。订阅任务随页面释放取消。
- **鉴权和重试**：在 resolver 中查询播放权限，两种请求用途 `.playback` 和 `.preload` 都要验证。拦截时返回 `.requiresUserAction`，由宿主显示解锁界面。授权成功后确认用户仍停留在原剧集，再调用 `retry()`。账号或权限范围变化时使用 `invalidateSources()` 清理已解析的地址和已准备的画面。
- **缓存和预加载**：`.preparedPlayer` 会预备相邻剧集的播放器。`.mediaBytes` 通过注入的 `PlaybackMediaCache` 预取媒体。默认缓存实现直接播放源地址。需要磁盘缓存、离线下载或 HLS 分片缓存时，在 App 中实现存储策略。
- **播放质量**：启动前订阅 `session.diagnostics()`，按 `attemptID` 统计首帧、卡顿、缓存回源和终止原因。用 `setStreamPreferences(_:)` 设置码率或缓冲偏好，用 `setPreloadPolicy(_:)` 运行时调整预加载。
- **横竖版与折叠屏**：用 `.fit` 保留完整画面，用 `.fill` 铺满播放区域。宿主用实际视图尺寸和安全区布局，通过同一个会话处理旋转、折叠和展开。正式适配 iPhone Duo 双屏全幅时，使用 Xcode 27.1 或更新版本构建宿主并验证各个姿态。 [Apple iPhone Duo 适配指南](https://developer.apple.com/iphone-duo/prepare/)

接入默认值、配置边界和日志开关见 [参数与调试参考](Configuration.zh-CN.md)。详细 API 用法见 [Integration guide](Usage.md)，对标依据及发行前验收见 [短剧播放生产指南](Production.zh-CN.md)。
