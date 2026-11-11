import SwiftUI

struct CityListView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var filter: Filter = .all

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
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.oceanDeep)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索城市")
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
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sections: [ProvinceSection] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        return app.boundary.provincesSorted.compactMap { province in
            let cities = app.boundary.cities(of: province.code).filter { city in
                guard keyword.isEmpty || city.name.contains(keyword) else { return false }
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

    private func row(_ city: Region) -> some View {
        let status: VisitStatus? = app.visits.isVisited(city.code)
            ? .visited
            : (app.visits.wishlistCodes.contains(city.code) ? .wishlist : nil)

        return Button {
            app.toggle(city)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.statusColor(status))
                    .frame(width: 7, height: 7)
                Text(city.name)
                    .font(.system(size: 14, weight: status == .visited ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundColor(status == .none ? Theme.textSecondary : .white)
                if app.pendingCodes.contains(city.code) {
                    Text("候选")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.pending, in: Capsule())
                }
                Spacer()
                Text(Theme.statusText(status))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.statusColor(status))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.oceanDeep)
    }
}
