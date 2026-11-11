import SwiftUI

/// 城市记录面板：点城市不再是「一点就变去过」，而是打开这张表，
/// 填「第一次去的时间」+「备注 / 故事」，点保存之后才进到去过名单里。
struct CityRecordSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let region: Region

    @State private var status: VisitStatus = .visited
    @State private var firstVisit = Date()
    @State private var note = ""
    @State private var prepared = false
    @State private var confirmRemove = false
    @FocusState private var noteFocused: Bool

    private var existing: Visit? { app.visits.visit(region.code) }

    private var provinceName: String {
        app.boundary.province(code: region.provinceCode)?.name ?? ""
    }

    private var isNew: Bool { existing == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionGap) {
                    headerCard
                    statusCard
                    if status == .visited {
                        dateCard
                        noteCard
                    }
                    if existing != nil {
                        removeCard
                    }
                    hintFooter
                }
                .padding(.horizontal, Theme.Layout.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(Theme.oceanDeep.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(Theme.Typo.label())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(Theme.Typo.label())
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("删除「\(region.name)」的记录？", isPresented: $confirmRemove,
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    app.removeRecord(region)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: prepare)
        .onChange(of: status) { _, newValue in
            if newValue == .wishlist { noteFocused = false }
        }
    }

    // MARK: - 顶部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(region.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(provinceName)
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
                Spacer(minLength: 0)
                statusBadge
            }
            if let visit = existing {
                Text(visit.summaryText)
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textSecondary)
                if visit.hasNote, !note.isEmpty, note != visit.note {
                    Text("备注已修改，保存后生效")
                        .font(Theme.Typo.caption())
                        .foregroundColor(Theme.pending)
                }
            } else {
                Text("还没记录过这个城市")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius,
                                                     style: .continuous))
    }

    private var statusBadge: some View {
        Text(status == .visited ? "去过" : "想去")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status == .visited ? Theme.brand : Theme.wish, in: Capsule())
    }

    // MARK: - 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("这个城市")
            HStack(spacing: 8) {
                statusButton(.visited, "去过", icon: "checkmark.circle.fill")
                statusButton(.wishlist, "想去", icon: "bookmark.fill")
            }
        }
        .cardStyle()
    }

    private func statusButton(_ value: VisitStatus, _ title: String, icon: String) -> some View {
        let active = status == value
        return Button {
            status = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(Theme.Typo.label())
            }
            .foregroundColor(active ? .black : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? (value == .visited ? Theme.brand : Theme.wish) : Theme.landDim,
                        in: RoundedRectangle(cornerRadius: Theme.Layout.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时间

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("第一次去是什么时候")
            DatePicker("第一次到达", selection: $firstVisit, in: ...Date(),
                       displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(Theme.Typo.body())
                .tint(Theme.brandLight)
            HStack(spacing: 8) {
                quickDate("今天", daysAgo: 0)
                quickDate("上周", daysAgo: -7)
                quickDate("上月", daysAgo: -30)
                quickDate("去年", daysAgo: -365)
            }
        }
        .cardStyle()
    }

    private func quickDate(_ title: String, daysAgo: Int) -> some View {
        Button {
            firstVisit = Calendar.current.date(byAdding: .day, value: daysAgo, to: Date()) ?? Date()
        } label: {
            Text(title)
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.landDim, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 备注

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("故事 / 备注")
                Spacer()
                Text("\(note.count)/500")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
            }
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("为什么来、和谁一起、吃了什么、当时的心情……")
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(Theme.Typo.body())
                    .scrollContentBackground(.hidden)
                    .focused($noteFocused)
                    .frame(minHeight: 132)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .onChange(of: note) { _, newValue in
                        if newValue.count > 500 { note = String(newValue.prefix(500)) }
                    }
            }
            .background(Theme.landDim, in: RoundedRectangle(cornerRadius: Theme.Layout.innerRadius,
                                                           style: .continuous))
        }
        .cardStyle()
    }

    // MARK: - 删除 / 说明

    private var removeCard: some View {
        Button {
            confirmRemove = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text("删除这条记录")
                    .font(Theme.Typo.label())
            }
            .foregroundColor(Color(red: 0.98, green: 0.42, blue: 0.42))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius,
                                                         style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hintFooter: some View {
        Text(isNew
             ? "保存之后，这个城市才会出现在「去过」里，并在地图上点亮。"
             : "改完点右上角「保存」生效。")
            .font(Theme.Typo.caption())
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - 逻辑

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let visit = existing {
            status = visit.status
            firstVisit = visit.firstSeen
            note = visit.note
        } else {
            status = app.visits.wishlistCodes.contains(region.code) ? .wishlist : .visited
            firstVisit = app.pendingCodes.contains(region.code)
                ? (app.visits.pendings[region.code]?.firstSeen ?? Date())
                : Date()
            note = ""
        }
    }

    private func save() {
        app.saveRecord(region, status: status, firstVisit: firstVisit, note: note)
        dismiss()
    }
}

// MARK: - 小工具

private extension View {
    /// 统一的卡片外观，后面加新卡片直接套这个修饰器就行
    func cardStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius,
                                                         style: .continuous))
    }
}

private extension CityRecordSheet {
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.caption())
            .foregroundColor(Theme.textSecondary)
    }
}
