import SwiftUI

// MARK: - 家与行程（主面板）

/// 两个新功能的入口：「把某座城市设为家」和「加一条从 A 到 B 的出行方式」。
struct TripsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickingHome = false
    @State private var addingLeg = false

    var body: some View {
        NavigationStack {
            List {
                homeSection
                legsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("家与行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .sheet(isPresented: $pickingHome) {
                CityPickerSheet(title: "选一座城市作为家",
                                selected: app.homeRegion) { region in
                    app.setHome(region)
                }
            }
            .sheet(isPresented: $addingLeg) {
                AddLegSheet()
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    // MARK: 家

    @ViewBuilder
    private var homeSection: some View {
        Section {
            if let home = app.homeRegion {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.gold.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "house.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.gold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.name)
                            .font(Theme.Typo.label())
                            .foregroundColor(Theme.textPrimary)
                        Text("地球上会为它亮一盏灯")
                            .font(Theme.Typo.caption())
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Button("换一座") { pickingHome = true }
                        .font(Theme.Typo.caption())
                        .buttonStyle(.borderless)
                }

                Button(role: .destructive) {
                    app.setHome(nil)
                } label: {
                    Text("取消「家」")
                        .font(Theme.Typo.body())
                }
            } else {
                Button {
                    pickingHome = true
                } label: {
                    Label("选一座城市作为家", systemImage: "house")
                        .font(Theme.Typo.body())
                }
            }
        } header: {
            Text("家")
        } footer: {
            Text("设了家之后：地球上会亮起一枚金色标记，带一圈慢慢呼吸的光环，还有一束沿球面挑出去的光柱；最近的 8 座去过的城市会从家拉出很淡的归家线，家周围也有一小片暖光。")
                .font(Theme.Typo.caption())
        }
    }

    // MARK: 行程

    private var legsSection: some View {
        Section {
            Button {
                addingLeg = true
            } label: {
                Label("添加一条出行", systemImage: "plus.circle.fill")
                    .font(Theme.Typo.body())
            }

            ForEach(app.trips.legs) { leg in
                legRow(leg)
            }
            .onDelete { offsets in
                let legs = app.trips.legs
                for index in offsets where index < legs.count {
                    app.removeLeg(legs[index].id)
                }
            }
        } header: {
            HStack {
                Text("出行方式")
                Spacer()
                Text("\(app.trips.showcasedCount) / \(TripStore.maxShowcase) 条在地球上")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
            }
        } footer: {
            Text("点右边的眼睛决定哪几条出现在地球上，最多同时 \(TripStore.maxShowcase) 条。飞机会沿大圆航线在天上飞、航迹是虚线；高铁、火车、汽车、船和徒步贴着地面跑。它们会按行进方向转过来，来回循环。")
                .font(Theme.Typo.caption())
        }
    }

    private func legRow(_ leg: TripLeg) -> some View {
        HStack(spacing: 10) {
            Image(systemName: leg.mode.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(leg.mode.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(cityName(leg.fromCode)) → \(cityName(leg.toCode))")
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.textPrimary)
                Text("\(leg.mode.title) · \(distanceText(leg))")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button {
                app.toggleLegShowcase(leg.id)
            } label: {
                Image(systemName: leg.showcased ? "eye.fill" : "eye.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(leg.showcased ? Theme.brand : Theme.textTertiary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
        }
    }

    private func cityName(_ code: String) -> String {
        app.boundary.city(code: code)?.shortName ?? "—"
    }

    private func distanceText(_ leg: TripLeg) -> String {
        guard let from = app.boundary.city(code: leg.fromCode)?.center,
              let to = app.boundary.city(code: leg.toCode)?.center else { return "" }
        let km = Int(GreatCircle.distanceKm(from, to).rounded())
        return "\(km) 公里"
    }
}

// MARK: - 添加一条出行

struct AddLegSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var from: Region?
    @State private var to: Region?
    @State private var mode: TransportMode = .plane
    @State private var picking: Endpoint?

    private enum Endpoint: String, Identifiable {
        case from
        case to
        var id: String { rawValue }
        var title: String { self == .from ? "从哪儿出发" : "去哪儿" }
    }

    private var ready: Bool {
        guard let from, let to else { return false }
        return from.code != to.code
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    endpointRow("出发", region: from) { picking = .from }
                    endpointRow("到达", region: to) { picking = .to }
                } header: {
                    Text("路线")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                              spacing: 8) {
                        ForEach(TransportMode.allCases) { item in
                            modeChip(item)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("怎么走")
                } footer: {
                    Text(mode.hint)
                        .font(Theme.Typo.caption())
                }

                Section {
                    Button {
                        guard let from, let to else { return }
                        if app.addLeg(from: from, to: to, mode: mode) { dismiss() }
                    } label: {
                        Text("添加")
                            .font(Theme.Typo.label())
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Layout.controlHeight)
                            .foregroundColor(.white)
                            .background(ready ? Theme.brand : Theme.textTertiary.opacity(0.4),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("添加出行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .sheet(item: $picking) { endpoint in
                CityPickerSheet(title: endpoint.title,
                                selected: endpoint == .from ? from : to) { region in
                    if endpoint == .from { from = region } else { to = region }
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func endpointRow(_ title: String, region: Region?,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(region?.name ?? "选择城市")
                    .font(Theme.Typo.label())
                    .foregroundColor(region == nil ? Theme.textTertiary : Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func modeChip(_ item: TransportMode) -> some View {
        let selected = item == mode
        return Button {
            mode = item
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(selected ? .white : item.tint)
            .background(selected ? item.tint : item.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 选城市

struct CityPickerSheet: View {
    let title: String
    let selected: Region?
    let onPick: (Region) -> Void

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [Region] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = app.boundary.cities
        guard !keyword.isEmpty else {
            return all.sorted { $0.name < $1.name }
        }
        return all.filter { $0.name.contains(keyword) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List(results) { region in
                Button {
                    onPick(region)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(region.name)
                            .font(Theme.Typo.body())
                            .foregroundColor(Theme.textPrimary)
                        if app.isHome(region.code) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.gold)
                        }
                        Spacer()
                        if let province = app.boundary.province(of: region) {
                            Text(province.shortName)
                                .font(Theme.Typo.caption())
                                .foregroundColor(Theme.textTertiary)
                        }
                        if selected?.code == region.code {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.brand)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜城市名")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

// MARK: - 交通方式的一句话说明

extension TransportMode {
    var hint: String {
        switch self {
        case .plane: return "飞机：抬得最高，沿大圆航线在空中飞，航迹是一条虚线弧"
        case .highSpeed: return "高铁：贴地快跑，线条最亮"
        case .train: return "火车：比高铁低一点、慢一点"
        case .car: return "汽车：几乎贴着地面"
        case .ship: return "船：走海面，会按航向转过来"
        case .walk: return "徒步：最小的一颗，几乎贴着球面"
        }
    }
}
