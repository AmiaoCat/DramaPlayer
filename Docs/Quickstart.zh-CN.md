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
| Single video | 点击视频暂停，拖动进度条或切换倍速。片段播完后循环。 | `SinglePlaybackView`、`.loop` |
| Landscape video | 播放内置 16:9 片段时旋转手机，对照横屏和竖屏下的完整画面与播放进度。 | `PlaybackVideoScaling.fit`、`SinglePlaybackView` |
| Video layouts | 横版和竖版样片可切换 12 套布局。打开 **Mini player** 后拖动顶部或右下角，也可在 **Custom size** 分别输入宽和高。 | `PlaybackLayoutTemplate.presets`、`PlaybackMiniPlayerView` |
| Vertical feed | 上下滑动或点击 **Episodes** 跳集。播完自动进入下一集，末集播完停止。 | `VerticalPlaybackView`、`select(_:)`、`.preparedPlayer`、`.advance` |
| Custom controls | 按 **Play** 从第 2 秒开始，按 **+5 seconds** 快进，播完按 **Replay**。 | `PlaybackVideoView`、`resumePosition`、`events()`、`seek(to:)` |
| Episode access | 第 2 集显示 **Access required**。按 **Unlock episode** 后播放。返回菜单重新进入可再次体验锁定状态。 | `.requiresUserAction`、`retry()` |
| Cache policies | 切换 **Off**、**Players**、**Media bytes**。在 **Media bytes** 下等第 2 集显示 **Prefetched** 后选中它，查看 **Cache hit**。按 **Reset** 从第 1 集和空缓存重新开始。 | `PlaybackConfiguration.Preload`、`PlaybackCacheAdapter` |
| Remote playback | 输入直连 HTTPS 地址或选择 **Apple HLS sample**。查看首帧耗时，在 **Playback** 菜单切换省流偏好、音轨或字幕。失败后可点击 **Retry playback**。 | `diagnostics()`、`setStreamPreferences(_:)`、`mediaTrackGroup(for:)` |

## 接入业务数据

- **进度和完播**：通过 `session.events()` 读取 `.snapshot` 和 `.ended(id)`。进度单位是秒。按剧集 ID 保存退出时的进度，下次构建 `PlaybackItem` 时传入 `resumePosition`。订阅任务随页面释放取消。
- **鉴权和重试**：在 resolver 中查询播放权限，两种请求用途 `.playback` 和 `.preload` 都要验证。拦截时返回 `.requiresUserAction`，由宿主显示解锁界面。授权成功后确认用户仍停留在原剧集，再调用 `retry()`。账号或权限范围变化时使用 `invalidateSources()` 清理已解析的地址和已准备的画面。
- **缓存和预加载**：`.preparedPlayer` 会预备相邻剧集的播放器。`.mediaBytes` 通过注入的 `PlaybackMediaCache` 预取媒体。默认缓存实现直接播放源地址。需要磁盘缓存、离线下载或 HLS 分片缓存时，在 App 中实现存储策略。
- **播放质量**：启动前订阅 `session.diagnostics()`，按 `attemptID` 统计首帧、卡顿、缓存回源和终止原因。用 `setStreamPreferences(_:)` 设置码率或缓冲偏好，用 `setPreloadPolicy(_:)` 运行时调整预加载。
- **横竖版与折叠屏**：用 `.fit` 保留完整画面，用 `.fill` 铺满播放区域。宿主用实际视图尺寸和安全区布局，通过同一个会话处理旋转、折叠和展开。正式适配 iPhone Duo 双屏全幅时，使用 Xcode 27.1 或更新版本构建宿主并验证各个姿态。 [Apple iPhone Duo 适配指南](https://developer.apple.com/iphone-duo/prepare/)

接入默认值、配置边界和日志开关见 [参数与调试参考](Configuration.zh-CN.md)。详细 API 用法见 [Integration guide](Usage.md)，对标依据及发行前验收见 [短剧播放生产指南](Production.zh-CN.md)。
