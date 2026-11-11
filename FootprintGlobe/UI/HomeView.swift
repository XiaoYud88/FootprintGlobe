import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel

    @State private var lastDrag: CGSize = .zero
    @State private var pinchBase: Double?
    @State private var showCities = false
    @State private var showPending = false
    @State private var showSettings = false

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
                    app.setZoom(app.zoom + 1.1)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 10)

            toastLayer
        }
        .animation(.easeInOut(duration: 0.3), value: app.isGlobe)
        .animation(.easeInOut(duration: 0.25), value: app.toast)
        .sheet(isPresented: $showCities) { CityListView() }
        .sheet(isPresented: $showPending) { PendingListView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { app.start() }
    }

    private var pendingCities: [Region] {
        app.visits.pendingList.compactMap { app.boundary.city(code: $0.code) }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("足迹地球")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(1.5)
                Text("\(app.progressText) 城市 · \(app.visits.provinceCount) 省份")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            ProgressRing(progress: app.cityProgress)
                .frame(width: 36, height: 36)
            iconButton("list.bullet") { showCities = true }
            iconButton("gearshape.fill") { showSettings = true }
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 10) {
            if let city = app.currentCity {
                currentCityChip(city)
            }
            if app.location.needsPermissionPrompt {
                permissionCard
            }
            controlBar
        }
    }

    private func currentCityChip(_ city: Region) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.visits.isVisited(city.code) ? Theme.brand : Theme.pending)
                .frame(width: 7, height: 7)
            Text(city.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(app.visits.isVisited(city.code) ? "已记录" : "候选确认中")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            barButton(app.isGlobe ? "plus.magnifyingglass" : "globe.asia.australia.fill",
                      app.isGlobe ? "进入中国" : "回到地球") {
                if app.isGlobe { app.enterChina() } else { app.backToGlobe() }
            }
            barButton("clock.badge.questionmark", "待确认", badge: app.visits.pendings.count) {
                showPending = true
            }
            barButton("location.fill", nil) {
                app.focusOnMe()
            }
        }
    }

    private func barButton(_ icon: String, _ title: String?, badge: Int = 0,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.pending, in: Capsule())
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .foregroundColor(Theme.pending)
                Text("开启定位才能自动打卡")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Text("需要「使用 App 期间」+「始终」定位权限。位置只在本机计算，不会上传；判定规则是「同一城市隔 3 小时还在」才算去过。")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.location.requestPermission()
            } label: {
                Text(app.location.status == .denied ? "去系统设置开启" : "允许定位")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.brand, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    .padding(.top, 104)
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
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                app.pan(dx: delta.width, dy: delta.height, size: size)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchBase == nil { pinchBase = app.zoom }
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
