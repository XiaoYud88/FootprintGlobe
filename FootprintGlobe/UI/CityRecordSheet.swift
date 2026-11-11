import SwiftUI
import PhotosUI

/// 城市记录面板：点城市不再是「一点就变去过」，而是打开这张表，
/// 填「第一次去的时间」+「故事」+「照片」+「标签 / 心情」+「星级」，点保存之后才进到去过名单里。
struct CityRecordSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let region: Region

    @State private var status: VisitStatus = .visited
    @State private var firstVisit = Date()
    @State private var note = ""
    @State private var tags: [String] = []
    @State private var rating = 0
    @State private var photos: [String] = []

    /// 这次新加进来的照片文件名：取消时要删掉，避免留下孤儿文件
    @State private var addedPhotos: Set<String> = []
    @State private var originalPhotos: [String] = []

    @State private var pickerItem: PhotosPickerItem?
    @State private var customTag = ""
    @State private var prepared = false
    @State private var confirmRemove = false
    @FocusState private var noteFocused: Bool

    private var existing: Visit? { app.visits.visit(region.code) }

    private var provinceName: String {
        app.boundary.province(code: region.provinceCode)?.name ?? ""
    }

    private var isNew: Bool { existing == nil }

    private var maxPhotos: Int { Theme.Layout.maxPhotosPerCity }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionGap) {
                    headerCard
                    statusCard
                    if status == .visited {
                        dateCard
                        noteCard
                        photoCard
                        tagCard
                        ratingCard
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
                    Button("取消") { cancel() }
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
        .preferredColorScheme(Theme.colorScheme)
        .onAppear(perform: prepare)
        .onChange(of: pickerItem) { _, item in loadPhoto(item) }
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
        .themeCard()
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
        .themeCard()
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
        .themeCard()
    }

    // MARK: - 照片（每个城市最多 3 张，只在记录 / 清单 / 护照页出现）

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("照片")
                Spacer()
                Text("\(photos.count)/\(maxPhotos)")
                    .font(Theme.Typo.caption())
                    .foregroundColor(photos.count >= maxPhotos ? Theme.pending : Theme.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(photos, id: \.self) { name in
                    photoThumb(name)
                }
                if photos.count < maxPhotos {
                    addPhotoButton
                }
                Spacer(minLength: 0)
            }

            Text("最多 \(maxPhotos) 张；只在记录、清单、护照页出现，不会画到地球和地图上。")
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .themeCard()
    }

    private func photoThumb(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = PhotoStore.shared.thumbnail(name, side: 220) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.landDim
                        .overlay(Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textTertiary))
                }
            }
            .frame(width: 74, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                removePhoto(name)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
    }

    private var addPhotoButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("加照片")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(Theme.textSecondary)
            .frame(width: 74, height: 74)
            .background(Theme.landDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    // MARK: - 标签 / 心情

    private var tagCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("标签 / 心情")
                Spacer()
                Text("选几个当时的场景")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(TagCatalog.presets, id: \.self) { tag in
                    chip(tag, selected: tags.contains(tag)) {
                        toggleTag(tag)
                    }
                }
                ForEach(customOnlyTags, id: \.self) { tag in
                    chip(tag, selected: true) {
                        toggleTag(tag)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("自定义标签", text: $customTag)
                    .font(Theme.Typo.body())
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(addCustomTag)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.landDim,
                                in: RoundedRectangle(cornerRadius: Theme.Layout.innerRadius,
                                                     style: .continuous))
                Button(action: addCustomTag) {
                    Text("添加")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.brandLight, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(TagCatalog.normalize(customTag) == nil)
            }
        }
        .themeCard()
    }

    /// 用户自己加的、不在预设里的标签
    private var customOnlyTags: [String] {
        tags.filter { !TagCatalog.presets.contains($0) }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundColor(selected ? .black : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selected ? Theme.brandLight : Theme.landDim,
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 星级

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("这次值几颗星")
                Spacer()
                if rating > 0 {
                    Text("\(rating) 星")
                        .font(Theme.Typo.caption())
                        .foregroundColor(Theme.gold)
                }
            }
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        rating = (rating == index) ? 0 : index
                    } label: {
                        Image(systemName: index <= rating ? "star.fill" : "star")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(index <= rating ? Theme.gold : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .themeCard()
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
            tags = visit.tags
            rating = visit.rating
            photos = visit.photos
            originalPhotos = visit.photos
        } else {
            status = app.visits.wishlistCodes.contains(region.code) ? .wishlist : .visited
            firstVisit = app.pendingCodes.contains(region.code)
                ? (app.visits.pendings[region.code]?.firstSeen ?? Date())
                : Date()
            note = ""
            tags = []
            rating = 0
            photos = []
            originalPhotos = []
        }
    }

    private func toggleTag(_ tag: String) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else if tags.count < 8 {
            tags.append(tag)
        }
    }

    private func addCustomTag() {
        guard let tag = TagCatalog.normalize(customTag), !tags.contains(tag), tags.count < 8 else {
            customTag = ""
            return
        }
        tags.append(tag)
        customTag = ""
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                defer { pickerItem = nil }
                guard let data, let jpeg = PhotoStore.downscale(data) else { return }
                guard photos.count < maxPhotos else { return }
                guard let name = PhotoStore.shared.save(jpeg, for: region.code) else { return }
                photos.append(name)
                addedPhotos.insert(name)
            }
        }
    }

    private func removePhoto(_ name: String) {
        photos.removeAll { $0 == name }
        if addedPhotos.contains(name) {
            // 这次才加的，直接删文件
            PhotoStore.shared.delete(name)
            addedPhotos.remove(name)
        }
    }

    private func cancel() {
        // 取消时把这次新加的照片清掉，别留下没人引用的文件
        for name in addedPhotos { PhotoStore.shared.delete(name) }
        addedPhotos.removeAll()
        dismiss()
    }

    private func save() {
        app.saveRecord(region, status: status, firstVisit: firstVisit, note: note,
                       tags: tags, rating: rating, photos: photos)
        // 被移除的旧照片，文件一起删掉
        for name in originalPhotos where !photos.contains(name) {
            PhotoStore.shared.delete(name)
        }
        dismiss()
    }
}

// MARK: - 小工具

private extension CityRecordSheet {
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.caption())
            .foregroundColor(Theme.textSecondary)
    }
}
