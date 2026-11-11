import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var dwellHours: Double = 3
    @State private var minSamples: Int = 2
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
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

                Section("数据") {
                    HStack {
                        Text("已记录城市")
                        Spacer()
                        Text("\(app.visits.cityCount) / \(app.boundary.cityCount)")
                            .foregroundColor(Theme.textSecondary)
                    }
                    HStack {
                        Text("待确认候选")
                        Spacer()
                        Text("\(app.visits.pendingList.count)")
                            .foregroundColor(Theme.textSecondary)
                    }
                    Button("清空所有记录", role: .destructive) {
                        showResetConfirm = true
                    }
                }

                Section {
                    Text("边界数据来自 DataV GeoAtlas（GCJ-02），已按显示精度简化后打包在 App 内，约 2.4 MB，全程离线、不需要联网、不需要账号。定位坐标只在本机计算，不会上传。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("0.1.0 (M0)")
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
        .preferredColorScheme(.dark)
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
