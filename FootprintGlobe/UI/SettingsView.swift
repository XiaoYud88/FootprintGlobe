import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var dwellHours: Double = 3
    @State private var minSamples: Int = 2
    @State private var showResetConfirm = false
    @State private var notifyOn = false

    // 备份 / 恢复
    @State private var busy = false
    @State private var backupURL: URL?
    @State private var backupSummary: BackupService.Summary?
    @State private var backups: [URL] = []
    @State private var showImporter = false
    @State private var restoreTarget: URL?
    @State private var restoreSummary: BackupService.Summary?
    @State private var showRestoreConfirm = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: 外观
                Section {
                    Picker("主题", selection: $app.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("外观")
                } footer: {
                    Text("手动切换，不跟随系统。选好之后立即生效，下次打开还是这个主题。")
                        .font(.system(size: 11, design: .rounded))
                }

                // MARK: 提醒
                Section {
                    Toggle("到访提醒", isOn: $notifyOn)
                        .onChange(of: notifyOn) { _, newValue in
                            Task { await applyNotify(newValue) }
                        }
                    HStack {
                        Text("通知权限")
                        Spacer()
                        Text(app.notifications.authorized ? "已允许" : "未允许")
                            .foregroundColor(Theme.textSecondary)
                    }
                    if !app.notifications.authorized {
                        Button("去允许通知") {
                            Task {
                                let ok = await app.notifications.requestAuthorization()
                                notifyOn = ok
                                app.notifications.setEnabled(ok)
                            }
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("在一个新城市待够 1 小时后，本地弹一条通知提醒你记录（不需要联网，也不会上传位置）。")
                        .font(.system(size: 11, design: .rounded))
                }

                // MARK: 判定规则
                Section {
                    Picker("停留阈值", selection: $dwellHours) {
                        Text("2 小时").tag(2.0)
                        Text("3 小时").tag(3.0)
                        Text("4 小时").tag(4.0)
                        Text("6 小时").tag(6.0)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $minSamples, in: 2...5) {
                        HStack {
                            Text("最少采样次数")
                            Spacer()
                            Text("\(minSamples) 次")
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("判定规则")
                } footer: {
                    Text("只有「同一城市、至少 \(minSamples) 次独立定位、时间跨度超过 \(Int(dwellHours)) 小时」才会记为去过。高铁/开车路过不会进名单。")
                        .font(.system(size: 11, design: .rounded))
                }

                // MARK: 定位
                Section("定位") {
                    HStack {
                        Text("权限状态")
                        Spacer()
                        Text(statusText)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Button("立即定位一次") {
                        app.location.refreshNow()
                    }
                    if app.location.isDenied {
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    if let error = app.location.lastError {
                        Text(error)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(Theme.pending)
                    }
                }

                // MARK: 备份与恢复
                Section {
                    Button {
                        runBackup()
                    } label: {
                        HStack {
                            Text("立即备份")
                            Spacer()
                            if busy {
                                ProgressView().scaleEffect(0.8)
                            } else if let summary = backupSummary {
                                Text(summary.sizeText)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .disabled(busy)

                    if let url = backupURL {
                        ShareLink(item: url) {
                            Label("导出刚做好的备份", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, design: .rounded))
                        }
                    }

                    Button("从文件恢复…") { showImporter = true }

                    ForEach(backups, id: \.self) { url in
                        Button {
                            preview(url)
                        } label: {
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12, design: .rounded))
                                    .lineLimit(1)
                                Spacer()
                                Text(fileSizeText(url))
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                    }
                } header: {
                    Text("备份与恢复")
                } footer: {
                    Text("备份包是一个普通 zip（记录 + 照片），可以存到「文件」或隔空投送出去。恢复会覆盖当前全部记录，所以恢复前会先问你一次。最近 \(BackupService.keepCount) 份自动留在这里。")
                        .font(.system(size: 11, design: .rounded))
                }

                // MARK: 数据
                Section {
                    row("已记录城市", "\(app.visits.cityCount) / \(app.boundary.cityCount)")
                    row("省级行政区", "\(app.visits.provinceCount) / \(app.boundary.provinceCount)")
                    row("有故事的城市", "\(app.storyCount)")
                    row("照片", "\(app.photoCount)")
                    row("已点亮面积", app.stats.areaText)
                    row("面积覆盖率", app.stats.areaRatioText)
                    row("待确认候选", "\(app.visits.pendingList.count)")
                    Button("清空所有记录", role: .destructive) {
                        showResetConfirm = true
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("面积按球面多边形累加，分母是中国 + 日本；南极、北极单独成项，不掺进比例里。")
                        .font(.system(size: 11, design: .rounded))
                }

                // MARK: 关于
                Section {
                    Text("边界数据：中国来自 DataV GeoAtlas（GCJ-02），日本都道府县来自公开 GeoJSON，世界陆地与南极来自 Natural Earth，全部简化后打包在 App 内，约 3 MB，全程离线、不需要联网、不需要账号。定位坐标只在本机计算，不会上传。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("0.4.0 (M1-V2)")
                            .foregroundColor(Theme.textTertiary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .onAppear {
                dwellHours = app.tracker.config.dwellHours
                minSamples = app.tracker.config.minSamples
                notifyOn = app.notifications.enabled
                refreshBackups()
                Task { await app.notifications.refreshAuthorization() }
            }
            .onChange(of: dwellHours) { _, newValue in
                app.tracker.config.dwellHours = newValue
            }
            .onChange(of: minSamples) { _, newValue in
                app.tracker.config.minSamples = newValue
            }
            .confirmationDialog("确定清空所有到访记录？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    app.visits.resetAll()
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("用这份备份覆盖当前记录？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
                Button("覆盖恢复", role: .destructive) { performRestore() }
                Button("取消", role: .cancel) { restoreTarget = nil }
            } message: {
                if let summary = restoreSummary {
                    Text("包里是 \(summary.contentsText)。当前 \(app.visits.cityCount) 个城市的记录会被替换掉。")
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.zip],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    preview(url)
                case .failure(let error):
                    show(title: "选择文件失败", message: error.localizedDescription)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func applyNotify(_ on: Bool) async {
        if on {
            let granted = await app.notifications.requestAuthorization()
            app.notifications.setEnabled(granted)
            if !granted {
                notifyOn = false
            }
        } else {
            app.notifications.setEnabled(false)
        }
    }

    private var statusText: String {
        switch app.location.status {
        case .notDetermined: return "未询问"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorizedWhenInUse: return "使用期间"
        case .authorizedAlways: return "始终允许"
        @unknown default: return "未知"
        }
    }

    // MARK: - 备份 / 恢复

    private func refreshBackups() {
        backups = BackupService.shared.existingBackups()
    }

    private func runBackup() {
        busy = true
        defer { busy = false }
        do {
            let url = try BackupService.shared.makeBackup(store: app.visits)
            backupURL = url
            backupSummary = try? BackupService.shared.inspect(url)
            refreshBackups()
            app.showToast("备份好了 · \(backupSummary?.sizeText ?? "")")
        } catch {
            show(title: "备份失败", message: error.localizedDescription)
        }
    }

    /// 先读包内容，让确认弹窗能说清楚「包里是什么」再覆盖
    private func preview(_ url: URL) {
        do {
            restoreSummary = try BackupService.shared.inspect(url)
            restoreTarget = url
            showRestoreConfirm = true
        } catch {
            show(title: "这个包打不开", message: error.localizedDescription)
        }
    }

    private func performRestore() {
        guard let url = restoreTarget else { return }
        busy = true
        defer {
            busy = false
            restoreTarget = nil
        }
        do {
            let summary = try BackupService.shared.restore(from: url, store: app.visits)
            refreshBackups()
            app.showToast("已恢复 \(summary.cityCount) 个城市")
        } catch {
            show(title: "恢复失败", message: error.localizedDescription)
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int) ?? 0
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
        return "\(max(1, bytes / 1024)) KB"
    }

    private func show(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
