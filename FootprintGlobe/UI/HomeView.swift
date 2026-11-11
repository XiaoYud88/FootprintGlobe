import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel

    // 手势
    @State private var lastDrag: CGSize = .zero
    @State private var dragging = false
    @State private var pinchBase: Double?

    // 弹层
    @State private var showCities = false
    @State private var showPending = false
    @State private var showSettings = false
    @State private var editingCity: Region?
    @State private var permissionDismissed = false

    var body: some View {
        ZStack {
            StarField()
                .ignoresSafeArea()

            GeometryReader { geo in
                Group {
                    if app.isGlobe {
                        GlobeView(center: app.center,
                                  radiusFactor: app.globeRadiusFactor,
                                  provinces: app.boundary.provinces,
                                  visitedProvinceCodes: app.visitedProvinceCodes,
                                  visitedCities: app.visitedCities,
                                  pendingCities: pendingCities,
                                  focus: app.focus)
                            .transition(.opacity)
                    } else {
                        ChinaMapView(center: app.center,
                                     lonSpan: app.lonSpan,
                                     detail: app.detail,
                                     provinces: app.boundary.provinces,
                                     cities: app.boundary.cities,
                                     visitedCityCodes: app.visitedCodes,
                                     wishlistCityCodes: app.visits.wishlistCodes,
                                     pendingCityCodes: app.pendingCodes,
                                     visitedProvinceCodes: app.visitedProvinceCodes,
                                     focus: app.focus)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SimultaneousGesture(dragGesture(size: geo.size), pinchGesture))
                .onTapGesture(count: 2) {
                    app.stepZoom(1.1)
                }
            }
            .ignoresSafeArea()

            // 顶部 / 底部 HUD（固定槽位，后面加组件只往里塞，不改结构）
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                bottomStack
            }
            .padding(.horizontal, Theme.Layout.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, Theme.Layout.floatGap)

            zoomRail

            toastLayer
        }
        .animation(.easeInOut(duration: 0.3), value: app.isGlobe)
        .animation(.easeInOut(duration: 0.22), value: app.toast)
        .sheet(isPresented: $showCities) { CityListView() }
        .sheet(isPresented: $showPending) { PendingListView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editingCity) { city in
            CityRecordSheet(region: city)
                .environmentObject(app)
        }
        .task { app.start() }
    }

    private var pendingCities: [Region] {
        app.visits.pendingList.compactMap { app.boundary.city(code: $0.code) }
    }

    // MARK: - 顶部槽位

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("足迹地球")
                    .font(Theme.Typo.title())
                    .tracking(1.2)
                Text(subtitle)
                    .font(Theme.Typo.subtitle())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                showCities = true
            } label: {
                ProgressRing(progress: app.cityProgress)
                    .frame(width: Theme.Layout.iconButton,
                           height: Theme.Layout.iconButton)
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        "\(app.visits.cityCount)/\(app.boundary.cityCount) 城市 · \(app.visits.provinceCount) 省 · \(app.storyCount) 段故事"
    }

    // MARK: - 右侧缩放导轨

    private var zoomRail: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                railButton("plus") { app.stepZoom(0.7) }
                Text(app.levelText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(app.isGlobe ? Theme.textSecondary : Theme.brandLight)
                    .frame(width: 40, height: 22)
                    .background(Theme.card.opacity(0.75), in: Capsule())
                railButton("minus") { app.stepZoom(-0.7) }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            .padding(.trailing, 12)
        }
    }

    private func railButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部槽位

    private var bottomStack: some View {
        VStack(spacing: Theme.Layout.floatGap) {
            if let city = app.currentCity {
                currentCityChip(city)
            }
            if showPermissionCard {
                permissionCard
            }
            dock
        }
    }

    private var showPermissionCard: Bool {
        app.location.needsPermissionPrompt && !permissionDismissed
    }

    private func currentCityChip(_ city: Region) -> some View {
        let visit = app.visits.visit(city.code)
        let isVisited = visit?.status == .visited
        return Button {
            editingCity = city
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isVisited ? Theme.brand : Theme.pending)
                    .frame(width: 7, height: 7)
                Text(city.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(isVisited ? (visit?.firstVisitText ?? "已记录") : "候选确认中")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var dock: some View {
        HStack(spacing: 6) {
            Button {
                if app.isGlobe { app.enterChina() } else { app.backToGlobe() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: app.isGlobe ? "plus.magnifyingglass" : "globe.asia.australia.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(app.isGlobe ? "进入中国" : "回到地球")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .frame(height: Theme.Layout.controlHeight)
                .background(Theme.brandLight, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 2)

            dockButton("clock.badge.questionmark", badge: app.visits.pendings.count) {
                showPending = true
            }
            dockButton("list.bullet") { showCities = true }
            dockButton("gearshape.fill") { showSettings = true }
        }
        .padding(Theme.Layout.dockPadding)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func dockButton(_ icon: String, badge: Int = 0,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: Theme.Layout.iconButton, height: Theme.Layout.iconButton)
                    .background(Color.white.opacity(0.06), in: Circle())
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.pending, in: Capsule())
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.pending)
                Text("开启定位才能自动打卡")
                    .font(Theme.Typo.label())
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { permissionDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            Text("需要「使用 App 期间」+「始终」定位权限。位置只在本机计算，不会上传；判定规则是「同一城市隔 3 小时还在」才算去过。")
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.location.requestPermission()
            } label: {
                Text(app.location.status == .denied ? "去系统设置开启" : "允许定位")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.pending, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius,
                                                             style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var toastLayer: some View {
        VStack {
            if let toast = app.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.brandLight, in: Capsule())
                    .shadow(color: Theme.brand.opacity(0.5), radius: 12)
                    .padding(.top, 92)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 手势

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    app.stopMomentum()
                }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                app.pan(dx: delta.width, dy: delta.height, size: size)
            }
            .onEnded { value in
                lastDrag = .zero
                dragging = false
                // 用系统预测的终点估算松手速度（多的那段大约 0.3 秒走完）
                let extra = CGSize(width: value.predictedEndTranslation.width - value.translation.width,
                                   height: value.predictedEndTranslation.height - value.translation.height)
                app.startMomentum(velocity: CGSize(width: extra.width / 0.3,
                                                   height: extra.height / 0.3),
                                  size: size)
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchBase == nil {
                    pinchBase = app.zoom
                    app.stopMomentum()
                    app.autoFollow = false
                }
                app.magnify(from: pinchBase ?? app.zoom, scale: scale)
            }
            .onEnded { _ in pinchBase = nil }
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AngularGradient(colors: [Theme.brand, Theme.brandLight, Theme.wish],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StarField: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(
                            Gradient(colors: [Color(red: 0.03, green: 0.035, blue: 0.06),
                                              Theme.oceanDeep]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: size.height)))

            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            for _ in 0..<150 {
                let x = Double(nextRandom(&seed)) * Double(size.width)
                let y = Double(nextRandom(&seed)) * Double(size.height)
                let r = 0.4 + Double(nextRandom(&seed)) * 1.1
                let alpha = 0.10 + Double(nextRandom(&seed)) * 0.55
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
    }

    private func nextRandom(_ seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((seed >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
    }
}
