import SwiftUI

struct CityListView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var tagFilter: String?
    @State private var editing: Region?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case visited = "去过"
        case wish = "想去"
        case unvisited = "没去过"

        var id: String { rawValue }
    }

    private struct ProvinceSection: Identifiable {
        let province: Region
        let cities: [Region]
        var id: String { province.code }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                if !app.allTags.isEmpty {
                    tagBar
                }
                if sections.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.oceanDeep)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索城市，也可以搜备注和标签")
            .navigationTitle("城市清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("筛选", selection: $filter) {
                            ForEach(Filter.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(Theme.Typo.label())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .sheet(item: $editing) { city in
                CityRecordSheet(region: city)
                    .environmentObject(app)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    /// 顶部概览：以后要加统计（按年份、按省份）就往这条带上加，不动列表结构
    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryItem("\(app.visits.cityCount)", "去过城市")
            divider
            summaryItem("\(app.visits.provinceCount)", "省份")
            divider
            summaryItem("\(app.storyCount)", "有故事")
            divider
            summaryItem("\(app.photoCount)", "照片")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Layout.pagePadding)
        .padding(.vertical, 10)
        .background(Theme.card.opacity(0.55))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 12)
    }

    private func summaryItem(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.Typo.number())
                .foregroundColor(Theme.textPrimary)
            Text(title)
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - 标签筛选

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagChip("全部标签", selected: tagFilter == nil) { tagFilter = nil }
                ForEach(app.allTags, id: \.self) { tag in
                    tagChip(tag, selected: tagFilter == tag) {
                        tagFilter = (tagFilter == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.pagePadding)
            .padding(.vertical, 8)
        }
        .background(Theme.card.opacity(0.3))
    }

    private func tagChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundColor(selected ? .black : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.brandLight : Theme.landDim, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.cities) { city in
                        row(city)
                    }
                } header: {
                    HStack {
                        Text(section.province.name)
                        Spacer()
                        let visited = section.cities.filter { app.visits.isVisited($0.code) }.count
                        Text("\(visited)/\(section.cities.count)")
                            .font(Theme.Typo.caption())
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var sections: [ProvinceSection] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        return app.boundary.provincesSorted.compactMap { province in
            let cities = app.boundary.cities(of: province.code).filter { city in
                guard keyword.isEmpty || matches(city, keyword) else { return false }
                if let tagFilter,
                   !(app.visits.visit(city.code)?.tags.contains(tagFilter) ?? false) {
                    return false
                }
                switch filter {
                case .all: return true
                case .visited: return app.visits.isVisited(city.code)
                case .wish: return app.visits.wishlistCodes.contains(city.code)
                case .unvisited: return !app.visits.isVisited(city.code)
                }
            }
            guard !cities.isEmpty else { return nil }
            return ProvinceSection(province: province, cities: cities)
        }
    }

    private func matches(_ city: Region, _ keyword: String) -> Bool {
        if city.name.contains(keyword) { return true }
        guard let visit = app.visits.visit(city.code) else { return false }
        if visit.trimmedNote.contains(keyword) { return true }
        return visit.tags.contains { $0.contains(keyword) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.textTertiary)
            Text(filter == .visited ? "还没有记录过城市" : "没有匹配的城市")
                .font(Theme.Typo.label())
            Text("点任意城市可以填「第一次去的时间」、故事、照片和标签。")
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 行

    private func row(_ city: Region) -> some View {
        let visit = app.visits.visit(city.code)
        let isVisited = visit?.status == .visited
        let isWish = visit?.status == .wishlist
        let status: VisitStatus? = isVisited ? .visited : (isWish ? .wishlist : nil)

        return Button {
            editing = city
        } label: {
            HStack(spacing: Theme.Layout.rowGap) {
                Circle()
                    .fill(Theme.statusColor(status))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(city.name)
                            .font(.system(size: 14, weight: isVisited ? .semibold : .regular,
                                          design: .rounded))
                            .foregroundColor(status == .none ? Theme.textSecondary : Theme.textPrimary)
                        if app.pendingCodes.contains(city.code) {
                            Text("候选")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.pending, in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if let visit, isVisited {
                            Text(visit.firstVisitYear)
                                .font(Theme.Typo.caption())
                                .foregroundColor(Theme.brandLight.opacity(0.85))
                        }
                    }

                    if let visit, isVisited {
                        HStack(spacing: 6) {
                            if visit.hasNote {
                                Text(visit.trimmedNote)
                                    .font(Theme.Typo.caption())
                                    .foregroundColor(Theme.textTertiary)
                                    .lineLimit(1)
                            } else {
                                Text(Theme.statusText(status))
                                    .font(Theme.Typo.caption())
                                    .foregroundColor(Theme.textTertiary)
                            }
                            if visit.rating > 0 {
                                Text(String(repeating: "★", count: visit.rating))
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.gold)
                            }
                            if visit.hasPhotos {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.brandLight)
                            }
                        }
                    } else {
                        Text(visit == nil ? "没去过" : Theme.statusText(status))
                            .font(Theme.Typo.caption())
                            .foregroundColor(Theme.textTertiary)
                    }

                    if let visit, isVisited, !visit.tags.isEmpty {
                        Text(visit.tagLine)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Theme.brandLight.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary.opacity(0.7))
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.oceanDeep)
    }
}
