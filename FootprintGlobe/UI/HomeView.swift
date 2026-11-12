import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var account = AccountService.shared

    // 手势
    @State private var lastDrag: CGSize = .zero
    @State private var dragging = false
    @State private var pinchBase: Double?

    // 弹层
    @State private var showCities = false
    @State private var showPending = false
    @State private var showSettings = false
    @State private var showPassport = false
    @State private var showTrips = false
    @State private var editingCity: Region?
    @State private var permissionDismissed = false

    var body: some View {
        ZStack {
            SkyView(appearance: app.appearance, centerLon: app.center.lon)
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
                                  focus: app.focus,
                                  countries: WorldStore.shared.loadIfNeeded(),
                                  parallax: app.parallax,
                                  appearance: app.appearance,
                                  home: app.homeCoord,
                                  homeArcs: app.homeArcs,
                                  legs: app.globeLegs,
                                  animated: true)
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
                                     focus: app.focus,
                                     appearance: app.appearance)
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
            celebrationLayer
        }
        .animation(.easeInOut(duration: 0.3), value: app.isGlobe)
        .animation(.easeInOut(duration: 0.22), value: app.toast)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: app.celebration)
        .sheet(isPresented: $showCities) { CityListView() }
        .sheet(isPresented: $showPending) { PendingListView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPassport) { PassportView().environmentObject(app) }
        .sheet(isPresented: $showTrips) { TripsView() }
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
            if account.signedIn {
                Button {
                    showSettings = true
                } label: {
                    AvatarView(name: account.displayName, image: account.avatar, size: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我的账号")
            }
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
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .padding(.trailing, 12)
        }
    }

    private func railButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06),
                            in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部槽位

    private var bottomStack: some View {
        VStack(spacing: Theme.Layout.floatGap) {
            if let home = app.homeRegion {
                homeChip(home)
            }
            if let city = app.currentCity {
                currentCityChip(city)
            }
            if showPermissionCard {
                permissionCard
            }
            dock
        }
    }

    /// 设了家之后底部多出来的一枚金色小胶囊，点一下飞回家
    private func homeChip(_ home: Region) -> some View {
        Button {
            app.fly(to: home)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "house.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("家 · \(home.shortName)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if let km = homeDistanceText(home) {
                    Text(km)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.gold.opacity(0.72))
                }
            }
            .foregroundColor(Theme.gold)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.gold.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(Theme.gold.opacity(0.34), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    /// 离现在位置多远（没定位到就不显示）
    private func homeDistanceText(_ home: Region) -> String? {
        guard let focus = app.focus else { return nil }
        let km = GreatCircle.distanceKm(focus, home.center)
        if km < 1 { return "就在这儿" }
        return km < 1000 ? "\(Int(km.rounded())) km"
                         : String(format: "%.0f km", km)
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

            dockButton("rosette") { showPassport = true }
            dockButton("clock.badge.questionmark", badge: app.visits.pendings.count) {
                showPending = true
            }
            dockButton("list.bullet") { showCities = true }
            dockButton("house.fill") { showTrips = true }
            dockButton("gearshape.fill") { showSettings = true }
        }
        .padding(Theme.Layout.dockPadding)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }

    private func dockButton(_ icon: String, badge: Int = 0,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: Theme.Layout.iconButton, height: Theme.Layout.iconButton)
                    .background(Theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06),
                                in: Circle())
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

    // MARK: - 点亮动画

    @ViewBuilder
    private var celebrationLayer: some View {
        if let celebration = app.celebration {
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { app.dismissCelebration() }

                VStack(spacing: 12) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { ring in
                            Circle()
                                .stroke(Color.white.opacity(0.30 - Double(ring) * 0.08), lineWidth: 1)
                                .frame(width: 62 + CGFloat(ring) * 26,
                                       height: 62 + CGFloat(ring) * 26)
                        }
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("点亮")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.75))
                    Text(celebration.cityName)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if !celebration.provinceName.isEmpty {
                        Text(celebration.provinceName)
                            .font(Theme.Typo.caption())
                            .foregroundColor(.white.opacity(0.75))
                    }
                    if let milestone = celebration.milestone {
                        Text(milestone)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.gold, in: Capsule())
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .background(
                    LinearGradient(colors: [Theme.brand, Theme.brandDim],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: Theme.brand.opacity(0.55), radius: 26)
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    // MARK: - 手势

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let started = !dragging
                if started {
                    dragging = true
                    app.stopMomentum()
                }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                app.pan(dx: delta.width, dy: delta.height, size: size)

                // 转球音：地球被「摩擦」着转，滚得越快声音越明显
                if app.isGlobe {
                    let intensity = min(1, Double(hypot(delta.width, delta.height)) / 9)
                    if started {
                        RollSound.shared.begin(intensity: intensity)
                    } else {
                        RollSound.shared.update(intensity: intensity)
                    }
                }
            }
            .onEnded { value in
                lastDrag = .zero
                dragging = false
                RollSound.shared.end()
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
            .onEnded { _ in
                pinchBase = nil
                app.settleZoom()
            }
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.12),
                        lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AngularGradient(colors: [Theme.brand, Theme.brandLight, Theme.wish],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

