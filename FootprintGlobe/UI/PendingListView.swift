import SwiftUI

struct PendingListView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if app.visits.pendingList.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.oceanDeep)
            .navigationTitle("待确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            Section {
                ForEach(app.visits.pendingList) { pending in
                    row(pending)
                }
            } footer: {
                Text("规则：同一城市至少有 2 次独立定位采样、且时间跨度超过 \(Int(app.tracker.config.dwellHours)) 小时，才会自动确认为「去过」。系统若没在后台唤醒，这里会留下候选，你可以手动确认。")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ pending: PendingVisit) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pending.cityName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(app.visits.isVisited(pending.code) ? "已记录" : "候选")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.pending, in: Capsule())
                }
                Text("首次 \(pending.firstSeen.formatted(date: .abbreviated, time: .shortened)) · 停留 \(String(format: "%.1f", pending.spanHours)) 小时 · \(pending.sampleCount) 次采样")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                app.confirmPending(pending.code)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(Theme.brand, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                app.discardPending(pending.code)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.oceanDeep)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.textTertiary)
            Text("没有待确认的城市")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("在某个城市停留超过 \(Int(app.tracker.config.dwellHours)) 小时后，会自动出现在这里或直接记录。")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
