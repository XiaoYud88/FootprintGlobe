import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var dwellHours: Double = 3
    @State private var minSamples: Int = 2
    @State private var showResetConfirm = false
    @State private var notifyOn = false

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
                        Text("0.3.0 (M1-V1)")
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
}
