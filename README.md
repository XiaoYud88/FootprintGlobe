# 足迹地球 · FootprintGlobe

一个只给自己用的 iPhone App：打开就是一颗**自绘的 3D 地球**，用定位自动记录你去过的城市，去过的国家 → 省份 → 城市会随缩放逐级亮起来。

- 纯 SwiftUI，**零第三方地图 SDK**，不需要任何 API Key，不需要联网
- 只做中国大陆（34 个省级行政区 / 370 个地级市），边界数据打包在 App 内
- 最小单位是**地级市**（太原市、秦皇岛市……）
- 定位数据只在本机计算，不上传、不要账号

当前版本：**M0（0.1.0）**

---

## 一、已经做完的（M0）

| 能力 | 实现方式 |
| --- | --- |
| 自绘 3D 地球 | `Canvas` + 正交投影（orthographic），球体渐变 / 经纬网 / 大气光 / 明暗交界 |
| 中国轮廓 | 34 省 + 370 市的简化多边形，随地球一起旋转投影 |
| 三级轮廓 | 缩放 < 1.5 看地球；进入中国后 > 45° 看省轮廓，> 8° 看市轮廓，再放大出市名 |
| 去过 / 没去过 | 去过：品牌紫填充 + 描边 + 地球上的发光点；想去：青色虚线；候选：琥珀虚线 |
| 打开即聚焦 | 冷启动拿到定位后自动把地球转到你所在的位置 |
| 自动记录 | 核心定位 + 显著位移监控，后台也能被动补点 |
| **防误记** | 同一城市「≥2 次独立采样」且「时间跨度 ≥ 3 小时」才转正；高铁经过会被丢弃 |
| 手动兜底 | 城市场景列表（搜索 / 筛选 / 一键标记）、候选清单（确认 / 丢弃） |
| 数据存储 | `Application Support/footprint.json`，Codable 快照，纯本地 |
| 手势 | 单指拖动转地球 / 平移地图，双指捏合连续缩放（地球↔地图无缝过渡），双击放大 |

### 关键设计

**为什么能不用地图 SDK？** 因为只需要中国一个国家的行政边界。数据是离线的（2.4 MB），投影是在 `Canvas` 里自己算的，所以既没有配额、也没有网络依赖。

**坐标系。** 边界数据来自 DataV GeoAtlas，是 **GCJ-02**；iOS 的 `CLLocation` 是 **WGS-84**。所以在定位入口用 `GeoMath.wgs84ToGcj02` 转换一次，之后全链路都用 GCJ-02，不需要在绘制时反复纠偏。

**为什么不需要定时轮询？** iOS 不允许后台定时采样。这里用的是 `startMonitoringSignificantLocationChanges()`（显著位移被动唤醒，几乎不耗电）+ 前台 `requestLocation()`。系统没唤醒时，候选会留在「待确认」里让人手动确认。

**防误记的判定（`VisitTracker`）**

```
进城            → 只生成候选（不写记录）
候选            → sampleCount >= 2 且 spanHours >= 3   ⇒ 转正
离开时还没达标  → 丢弃（这就是高铁经过进不了名单的原因）
高速 + 停留极短 → 直接判为路过
已在名单再进城  → 只更新 lastSeen / sampleCount / 天数
```

停留阈值（2/3/4/6 小时）和最少采样次数（2–5 次）都能在设置里改。

---

## 二、怎么跑起来

环境：macOS + **Xcode 16 或更新**（iOS 17+ 真机 / 模拟器）。

1. 打开 `FootprintGlobe.xcodeproj`
2. 选中 `FootprintGlobe` target → **Signing & Capabilities**
   - 勾选 `Automatically manage signing`
   - `Team` 选你自己的 Apple ID（免费账号即可）
   - 如果 `Bundle Identifier` 冲突，把 `com.personal.footprintglobe` 改成任意唯一值
3. 手机连上电脑，选自己的设备，⌘R 运行
4. 首次启动按提示给定位权限：**使用 App 期间** + **始终允许**（后台补点必需）

> 用免费开发者账号签的 App，**7 天后会失效**，重新 ⌘R 一次即可；证书过期后桌面图标点开会闪退，属正常现象。

### 目录结构

```
FootprintGlobe/
├─ FootprintGlobeApp.swift     入口
├─ Core/
│  ├─ GeoCoord.swift           GeoCoord / BBox / GeoMath（含 WGS-84→GCJ-02）
│  ├─ Region.swift             行政区 + 预生成 Path + 射线法 + 0.5° 网格索引
│  ├─ BoundaryStore.swift      加载 boundaries.json，点→城市的命中查询
│  ├─ VisitModels.swift        Visit / PendingVisit / VisitStatus
│  ├─ VisitStore.swift         本地读写 footprint.json
│  ├─ VisitTracker.swift       停留确认状态机（防误记核心）
│  ├─ LocationService.swift    CLLocationManager 封装
│  └─ AppModel.swift           全局状态：相机、定位、数据、手动操作
├─ UI/
│  ├─ Theme.swift              配色
│  ├─ GlobeView.swift          自绘 3D 地球 + 正交投影
│  ├─ ChinaMapView.swift       等距圆柱投影平面图，三级详略 + 标签避让
│  ├─ HomeView.swift           主界面、手势、底部控制条
│  ├─ CityListView.swift       城市清单
│  ├─ PendingListView.swift    待确认候选
│  └─ SettingsView.swift       判定规则 / 定位 / 数据 / 关于
├─ Resources/boundaries.json   离线边界（34 省 / 370 市 / 13.4 万点 / 2.4 MB）
└─ Assets.xcassets             图标 + 主题色
```

---

## 三、边界数据

- 来源：阿里云 DataV GeoAtlas 行政区划（`_full.json`），坐标系 **GCJ-02**
- 处理：只保留外环 → Douglas–Peucker 简化（省 0.006°、市 0.004°）→ 丢弃跨度 < 0.035° 的碎岛 → 合并成单个 `boundaries.json`
- 规模：34 个省级、370 个地级市、134,352 个点、约 2.4 MB
- 加载耗时：真机 / 模拟器约 90 ms，一次性在启动时完成

数据仅供个人记录使用，版权归原数据提供方。

---

## 四、隐私

- 定位坐标只在本机做多边形判定，**不上传、不落第三方**
- 没有账号、没有埋点、没有网络请求（App 本身不需要联网权限）
- 所有记录保存在沙盒内，卸载 App 即彻底删除

---

## 五、下一步（M1 起）

- 城市详情：首次到访、停留天数、备注
- 旅程分段（把连续到访串成「一次旅行」）、极值统计（最北 / 最南 / 最东 / 最西）
- 年度报告、护照页、徽章
- 分享图导出（把地球渲染成一张海报）
- 愿望单（想去）的完整交互
- 更省电的后台策略：`BGAppRefreshTask` + `CLMonitor` 区域监听

## 已知限制

- 台湾省的市级数据源里只有省级轮廓，暂按一个整块显示
- 长时间静止时系统可能不唤醒，靠「待确认」手动兜底
- M0 还没有做 iCloud / 跨设备同步
