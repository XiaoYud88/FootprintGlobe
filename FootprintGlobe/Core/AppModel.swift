import SwiftUI
import Combine
import UIKit
import CoreLocation

enum DetailLevel {
    /// 只区分国家（整个中国轮廓）
    case country
    /// 省轮廓 + 去过的省高亮
    case province
    /// 市轮廓 + 城市名 + 去过的市高亮
    case city
}

/// 全局状态：相机（地球/中国平面图的连续缩放）、定位、到访数据。
@MainActor
final class AppModel: ObservableObject {
    // MARK: 相机
    /// 0 ... 8。`zoom < 1.5` 显示自绘 3D 地球，`>= 1.5` 显示中国平面图。
    @Published var zoom: Double = 0
    /// 当前视角中心（GCJ-02）
    @Published var center = GeoCoord.chinaCenter
    /// 我的位置（GCJ-02），没定位到时为 nil
    @Published var focus: GeoCoord?
    /// 当前所在城市
    @Published var currentCity: Region?
    /// 跟随定位
    @Published var autoFollow = true
    /// 轻提示
    @Published var toast: String?

    // MARK: 地球的自转 / 视差
    /// 闲置一会儿自动慢慢转（M1-V3 加的）
    @Published var autoRotate: Bool = true {
        didSet {
            guard oldValue != autoRotate else { return }
            UserDefaults.standard.set(autoRotate, forKey: Self.autoRotateKey)
            noteInteraction()
        }
    }

    static let autoRotateKey = "globe.autoRotate"
    /// 陀螺仪：手腕转动带出的轻微透视变化
    let motion = MotionService()

    private var lastInteraction = Date()
    private var rotateTask: Task<Void, Never>?
    private var introPlayed = false

    /// 视差偏移（单位是度）：球面跟着手机倾角轻轻挪，星空不动，于是有了层次。
    var parallax: CGSize {
        guard motion.enabled, isGlobe else { return .zero }
        return CGSize(width: motion.tiltX * 3.4, height: motion.tiltY * 2.6)
    }

    // MARK: 外观
    /// 深色 / 浅色，由用户在「设置」里手选，不跟随系统。
    @Published var appearance: AppearanceMode = .dark {
        didSet {
            guard oldValue != appearance else { return }
            Theme.mode = appearance
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    static let appearanceKey = "appearance.mode"

    // MARK: 点亮动画
    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let cityName: String
        let provinceName: String
        let milestone: String?
    }

    /// 非 nil 时首页弹一次「点亮」庆祝
    @Published var celebration: Celebration?

    // MARK: 数据
    let boundary = BoundaryStore.shared
    let visits: VisitStore
    let tracker: VisitTracker
    let location = LocationService()
    let notifications = NotificationService.shared

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init() {
        let store = VisitStore()
        self.visits = store
        self.tracker = VisitTracker(boundary: BoundaryStore.shared, visits: store)

        let savedMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "")
        self.appearance = savedMode ?? .dark
        Theme.mode = savedMode ?? .dark
        self.autoRotate = UserDefaults.standard.object(forKey: Self.autoRotateKey) as? Bool ?? true

        // 把 VisitStore 的变化转发出去，视图只订阅 AppModel 就够了
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        tracker.onUnlock = { [weak self] region in
            self?.showToast("新解锁 · \(region.name)")
            self?.celebrate(region)
        }

        tracker.onNewPending = { [weak self] region in
            guard let self, self.notifications.enabled else { return }
            self.notifications.notifyNewPending(cityName: region.name, code: region.code)
        }

        notifications.$openPendingRequest
            .sink { [weak self] open in
                guard let self, open else { return }
                self.showToast("有一条待确认的到访")
                self.notifications.openPendingRequest = false
            }
            .store(in: &cancellables)
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        notifications.bootstrap()
        location.onUpdate = { [weak self] location in
            Task { @MainActor in self?.handle(location) }
        }
        location.start()
        tracker.begin()
        motion.start()
        startAutoRotate()
        playIntro()
    }

    // MARK: - 自动旋转

    /// 24fps 就够顺滑，比 60fps 省电；每帧 0.16°，约 90 秒转一圈。
    private func startAutoRotate() {
        rotateTask?.cancel()
        rotateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 41_666_667)
                guard let self, !Task.isCancelled else { return }
                self.tickAutoRotate()
            }
        }
    }

    private func tickAutoRotate() {
        guard autoRotate, isGlobe, !autoFollow, zoom >= 0 else { return }
        // 手指刚离开 8 秒内不转，免得刚摆好角度就被带走
        guard Date().timeIntervalSince(lastInteraction) > 8 else { return }
        // 退到后台 / 弹窗挡住时不动，省电
        guard UIApplication.shared.applicationState == .active else { return }

        var lon = center.lon + 0.16
        if lon > 180 { lon -= 360 }
        center = GeoCoord(lon: lon, lat: center.lat)
    }

    /// 任何手动操作都调一下：重置「闲置计时」，顺便停掉惯性
    func noteInteraction() {
        lastInteraction = Date()
    }

    /// 静止多久之后开始自转（秒）
    static let idleBeforeRotate: TimeInterval = 8

    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastInteraction) }

    /// 启动动画：地球从很远的地方推近，配合星空淡入，打开就不再是「一张静态图」
    private func playIntro() {
        guard !introPlayed else { return }
        introPlayed = true
        zoom = -1.15
        withAnimation(.easeOut(duration: 1.35)) {
            zoom = 0
        }
    }

    private func handle(_ location: CLLocation) {
        let gcj = GeoMath.wgs84ToGcj02(GeoCoord(location.coordinate))
        focus = gcj
        currentCity = boundary.city(containing: gcj)
        if autoFollow {
            center = gcj
        }
        tracker.ingest(location)
    }

    // MARK: - 相机

    static let globeThreshold = 1.5
    static let maxZoom = 8.0

    var isGlobe: Bool { zoom < Self.globeThreshold }

    /// 屏幕宽度对应的经度跨度
    var lonSpan: Double { 200.0 / pow(2, zoom) }

    var globeRadiusFactor: Double {
        // 启动动画期间 zoom 会是负数（球从远处推近），这里留一个下限，别把球缩没了
        let z = max(-0.8, min(zoom, Self.globeThreshold))
        return 0.34 + 0.20 * z / Self.globeThreshold
    }

    var detail: DetailLevel {
        if isGlobe { return .country }
        if lonSpan > 45 { return .country }
        if lonSpan > 8 { return .province }
        return .city
    }

    /// 当前层级的中文名，给顶部/底部指示器用
    var levelText: String {
        if isGlobe { return "地球" }
        switch detail {
        case .country: return "国家"
        case .province: return "省份"
        case .city: return "城市"
        }
    }

    func setZoom(_ value: Double) {
        zoom = min(max(value, 0), Self.maxZoom)
    }

    func stepZoom(_ delta: Double) {
        stopMomentum()
        setZoom(zoom + delta)
    }

    func magnify(from base: Double, scale: CGFloat) {
        noteInteraction()
        let delta = log2(max(0.05, Double(scale)))
        // 超出上下限时留一点阻尼，手指能感觉到「到头了」，松手再弹回来
        let raw = base + delta
        if raw < 0 {
            zoom = raw * 0.32
        } else if raw > Self.maxZoom {
            zoom = Self.maxZoom + (raw - Self.maxZoom) * 0.32
        } else {
            zoom = raw
        }
    }

    /// 双指松手后把越界的缩放弹回合法区间
    func settleZoom() {
        guard zoom < 0 || zoom > Self.maxZoom else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            setZoom(zoom)
        }
    }

    func pan(dx: CGFloat, dy: CGFloat, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        noteInteraction()
        autoFollow = false
        if isGlobe {
            let radius = Double(min(size.width, size.height)) * globeRadiusFactor
            guard radius > 1 else { return }
            let degPerPoint = 110.0 / radius
            var lon = center.lon - Double(dx) * degPerPoint
            let lat = min(max(center.lat + Double(dy) * degPerPoint, -75), 75)
            lon = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360) - 180
            center = GeoCoord(lon: lon, lat: lat)
        } else {
            let pointsPerDegree = Double(size.width) / lonSpan
            guard pointsPerDegree > 0 else { return }
            let pointsPerLatDegree = pointsPerDegree / max(0.25, cos(center.lat * .pi / 180))
            // M1 起地图不再只有中国：日本、南极都在盘子里，边界放到世界范围
            let lon = min(max(center.lon - Double(dx) / pointsPerDegree, -180), 180)
            let lat = min(max(center.lat + Double(dy) / pointsPerLatDegree, -62), 78)
            center = GeoCoord(lon: lon, lat: lat)
        }
    }

    // MARK: - 惯性

    private var momentumTask: Task<Void, Never>?

    /// 松手后的滑行：以 60fps 继续平移，速度每帧乘 0.93，直到明显停下。
    /// 松手那一刻的速度由 `DragGesture.predictedEndTranslation` 估算（单位：点/秒）。
    func startMomentum(velocity: CGSize, size: CGSize) {
        momentumTask?.cancel()
        guard size.width > 0, size.height > 0 else { return }
        var vx = min(max(Double(velocity.width), -4200), 4200)
        var vy = min(max(Double(velocity.height), -4200), 4200)
        guard hypot(vx, vy) > 60 else { return }

        momentumTask = Task { [weak self] in
            let dt = 1.0 / 60.0
            var slowFrames = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_666_667)
                guard let self, !Task.isCancelled else { return }
                self.pan(dx: CGFloat(vx * dt), dy: CGFloat(vy * dt), size: size)
                vx *= 0.93
                vy *= 0.93
                if hypot(vx, vy) < 32 { slowFrames += 1 } else { slowFrames = 0 }
                if slowFrames >= 2 {
                    self.momentumTask = nil
                    return
                }
            }
        }
    }

    /// 手指再次按下 / 双指缩放 / 切换层级时立刻刹住
    func stopMomentum() {
        momentumTask?.cancel()
        momentumTask = nil
    }

    func enterChina() {
        stopMomentum()
        if let focus {
            center = focus
        }
        // 视野跨度约 65°，正好把中国放进屏幕（zoom 1.62 → lonSpan ≈ 65°）
        setZoom(max(zoom, 1.62))
    }

    func backToGlobe() {
        stopMomentum()
        if let focus {
            center = focus
        }
        setZoom(0)
    }

    /// 一键飞到某块区域（日本、南极、北极），护照页和清单里用。
    func fly(to region: Region) {
        stopMomentum()
        autoFollow = false
        center = region.center
        let spanLon = region.bounds.maxLon - region.bounds.minLon
        let spanLat = region.bounds.maxLat - region.bounds.minLat
        let span = max(3.0, max(spanLon, spanLat) * 1.5)
        let target = log2(200.0 / span)
        setZoom(min(Self.maxZoom, max(Self.globeThreshold + 0.1, target)))
    }

    func flyToJapan() {
        guard let japan = boundary.japanProvince else { return }
        fly(to: japan)
    }

    func focusOnMe() {
        autoFollow = true
        location.refreshNow()
        if let focus {
            center = focus
        }
        if zoom < 1 { setZoom(0) }
    }

    // MARK: - 手动操作

    func toggle(_ region: Region) {
        visits.toggle(code: region.code, region: region)
    }

    @discardableResult
    func markVisited(_ region: Region) -> Visit {
        visits.markVisited(region, manual: true)
    }

    func record(for code: String) -> Visit? { visits.visit(code) }

    /// 城市清单里「填表保存」的唯一入口：第一次去的时间 + 备注 + 标签 + 星级 + 照片。
    @discardableResult
    func saveRecord(_ region: Region, status: VisitStatus,
                    firstVisit: Date, note: String,
                    tags: [String] = [], rating: Int = 0,
                    photos: [String] = []) -> Visit {
        let wasVisited = visits.isVisited(region.code)
        let saved = visits.saveRecord(region, status: status, firstVisit: firstVisit,
                                      note: note, tags: tags, rating: rating, photos: photos)
        switch status {
        case .visited:
            showToast("已记录 · \(region.name)")
            if !wasVisited { celebrate(region) }
        case .wishlist:
            showToast("已加入想去 · \(region.name)")
        }
        return saved
    }

    // MARK: - 点亮动画

    /// 记录成功后弹一次庆祝：城市名 + 省份 + 里程碑（第 10 个城市之类）。
    func celebrate(_ region: Region, milestone: String? = nil) {
        let provinceName = boundary.province(of: region)?.name ?? ""
        let mark = milestone ?? milestoneText(nextCount: visits.cityCount)
        celebration = Celebration(cityName: region.name,
                                  provinceName: provinceName,
                                  milestone: mark)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self else { return }
            if self.celebration?.cityName == region.name { self.celebration = nil }
        }
    }

    func dismissCelebration() { celebration = nil }

    /// 只在「跨过整数关口」时给一句额外的话，避免每次都夸。
    private func milestoneText(nextCount count: Int) -> String? {
        switch count {
        case 1: return "第一座城市，出发了"
        case 5: return "第 5 座城市"
        case 10: return "第 10 座城市 · 行者"
        case 25: return "第 25 座城市 · 远行者"
        case 50: return "第 50 座城市 · 游侠"
        case 100: return "第 100 座城市 · 旅行家"
        case 200: return "第 200 座城市 · 大地行者"
        default: return nil
        }
    }

    func setTags(_ tags: [String], for code: String) { visits.setTags(tags, for: code) }
    func setRating(_ rating: Int, for code: String) { visits.setRating(rating, for: code) }
    func setPhotos(_ photos: [String], for code: String) { visits.setPhotos(photos, for: code) }

    func removeRecord(_ region: Region) {
        visits.remove(code: region.code)
        showToast("已移除 · \(region.name)")
    }

    func confirmPending(_ code: String) {
        guard let pending = visits.pendings[code] else { return }
        if let region = boundary.city(code: code) {
            visits.markVisited(region, manual: true)
        } else {
            visits.confirmPending(code: code)
        }
        visits.discardPending(code: pending.code)
        showToast("已加入 · \(pending.cityName)")
    }

    func discardPending(_ code: String) {
        visits.discardPending(code: code)
    }

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: - 统计

    var visitedCodes: Set<String> { visits.visitedCodes }
    var visitedProvinceCodes: Set<String> { visits.visitedProvinceCodes }
    var pendingCodes: Set<String> { visits.pendingCodes }

    var cityProgress: Double {
        boundary.cityCount > 0 ? Double(visits.cityCount) / Double(boundary.cityCount) : 0
    }

    var storyCount: Int { visits.storyCount }

    var photoCount: Int { visits.photoCount }
    var allTags: [String] { visits.allTags }

    /// 一次汇总的统计快照（护照页 / 设置页 / 徽章共用）
    var stats: TravelStats { TravelStats.make(boundary: boundary, store: visits) }

    func badges(for stats: TravelStats) -> [BadgeState] { BadgeCatalog.evaluate(stats) }

    var progressText: String { "\(visits.cityCount) / \(boundary.cityCount)" }

    var visitedCities: [Region] {
        visits.visitedCodes.compactMap { boundary.city(code: $0) }
    }

    var currentCityName: String {
        currentCity?.name ?? "未定位到城市"
    }
}
