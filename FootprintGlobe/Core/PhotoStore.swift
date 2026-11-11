import Foundation
import UIKit
import OSLog

/// 城市照片的存取。
///
/// 设计约定：
/// - 图片本体存在沙盒 `Application Support/FootprintGlobe/photos/` 下，
///   文件名是 `<城市code>-<时间戳>.jpg`；
/// - 「哪个城市有哪几张」这个关系存在 `Visit.photos` 里，跟记录一起走，
///   所以备份 / 恢复只要带上 json + photos 目录就行；
/// - **只在这几个地方出现**：城市记录面板、城市清单行的小角标、护照页统计。
///   绝不画到地球和地图上（用户明确要求主页保持干净）。
final class PhotoStore {
    static let shared = PhotoStore()

    /// 每个城市最多几张
    static var maxPerCity: Int { Theme.Layout.maxPhotosPerCity }

    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "photo")
    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FootprintGlobe", isDirectory: true)
        directory = base.appendingPathComponent("photos", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        cache.countLimit = 60
    }

    // MARK: - 写入

    /// 把一张原图压到最长边 1400 存盘，返回文件名。失败返回 nil。
    @discardableResult
    func save(_ data: Data, for code: String) -> String? {
        guard let jpeg = PhotoStore.downscale(data) else {
            log.error("downscale failed for \(code)")
            return nil
        }
        let name = "\(code)-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try jpeg.write(to: url, options: .atomic)
            return name
        } catch {
            log.error("save photo failed: \(error.localizedDescription)")
            return nil
        }
    }

    func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    // MARK: - 读取

    func image(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let url = directory.appendingPathComponent(name)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// 缩略图（列表 / 面板里的小方块），按尺寸单独缓存，避免整张大图解码进内存。
    func thumbnail(_ name: String, side: CGFloat) -> UIImage? {
        let key = "\(name)@\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = image(name) else { return nil }
        let scale = min(1, side / max(full.size.width, full.size.height))
        let size = CGSize(width: max(1, full.size.width * scale),
                          height: max(1, full.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { _ in
            full.draw(in: CGRect(origin: .zero, size: size))
        }
        cache.setObject(small, forKey: key)
        return small
    }

    /// 落盘文件里最大的图片总量（给设置页显示用）
    func diskUsageKB() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for item in items {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total / 1024
    }

    // MARK: - 压缩

    static func downscale(_ data: Data, maxSide: CGFloat = 1400) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        if scale > 0.98 {
            return image.jpegData(compressionQuality: 0.84)
        }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.84)
    }
}
