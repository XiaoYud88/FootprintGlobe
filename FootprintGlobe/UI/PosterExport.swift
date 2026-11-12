import SwiftUI
import UIKit
import Photos

/// 足迹海报：把「我去过多少、走到哪儿」压成一张能发出去的图。
///
/// 画法见 `PosterCanvas`——纯 Core Graphics，不走 `ImageRenderer`，所以不会再出现
/// 「点了分享弹出一片灰」的情况。
struct PosterData {
    var stats: TravelStats
    var provinces: [Region] = []
    var visitedProvinceCodes: Set<String> = []
    var visitedCities: [Region] = []
    var pendingCities: [Region] = []
    var countries: [WorldCountry] = []
    var center: GeoCoord = GeoCoord(lon: 105, lat: 30)
    var unlockedBadges: Int = 0
    var totalBadges: Int = BadgeCatalog.total
    var generatedAt: Date = Date()
    var version: String = "0.6.0"
}

// MARK: - 渲染

enum PosterRenderer {
    /// 渲染成 PNG 图片（几十毫秒，可以在主线程直接调）
    static func render(_ data: PosterData) -> UIImage? {
        PosterCanvas.image(data, detail: true)
    }

    /// 兜底：省掉世界陆地轮廓，更快；数据完全一样
    static func renderFallback(_ data: PosterData) -> UIImage? {
        PosterCanvas.image(data, detail: false)
    }
}

// MARK: - 系统分享

/// 直接让最顶层的控制器去弹 `UIActivityViewController`。
/// 之前是在 sheet 里再套一个 sheet，第三层经常弹成一片空白，这里绕开 SwiftUI 的嵌套。
enum SharePresenter {
    static func present(items: [Any]) {
        // 不比较 activationState（不同 SDK 里这个枚举的 case 名字变过），
        // 直接找带 key window 的那个 scene。
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        guard let window, var top = window.rootViewController else { return }

        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

// MARK: - 海报预览

/// 海报弹窗：先弹界面（转圈），再渲染。
struct PosterSheet: View {
    let data: PosterData

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var saved = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var usedFallback = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.oceanDeep.ignoresSafeArea()
                if let image {
                    preview(image)
                } else if failed {
                    failureView
                } else {
                    loadingView
                }
            }
            .navigationTitle("足迹海报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .task(id: attempt) { await makePoster() }
            .alert("没能存进相册", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } })) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func preview(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }

            if usedFallback {
                Text("这张是简化版（省掉了世界陆地轮廓），数据都是对的。")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                actionButton(saved ? "已存入相册" : (saving ? "保存中…" : "存到相册"),
                             symbol: saved ? "checkmark.circle.fill" : "photo.badge.plus") {
                    saveToAlbum(image)
                }
                actionButton("分享", symbol: "square.and.arrow.up") {
                    SharePresenter.present(items: [image])
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在画海报…")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var failureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textTertiary)
            Text("这张图没渲染出来")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
            Text("点下面重试一次。")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Button {
                failed = false
                image = nil
                attempt += 1
            } label: {
                Text("重新生成")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
                    .frame(height: Theme.Layout.controlHeight)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(_ title: String, symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Layout.controlHeight)
                .background(Theme.brand.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    /// 先让弹窗动画走完再出图，避免第一帧就被绘制卡住
    private func makePoster() async {
        guard image == nil else { return }
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else { return }

        if let rendered = PosterRenderer.render(data) {
            image = rendered
            return
        }
        if let fallback = PosterRenderer.renderFallback(data) {
            image = fallback
            usedFallback = true
            return
        }
        failed = true
    }

    private func saveToAlbum(_ image: UIImage) {
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                errorText = "没有相册写入权限。可以到「设置 → 足迹地球 → 照片」里打开，或者直接用「分享」存到别处。"
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saved = true
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
