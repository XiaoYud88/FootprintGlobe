import Foundation
import OSLog

/// 备份 / 恢复。
///
/// 备份包就是一个普通 zip，里面有：
/// - `footprint.json`  全部记录（城市、待确认候选、备注、标签、星级）
/// - `travel.json`     家和出行方式（M2-V1 起，没有就不写这一条）
/// - `photos/<文件名>`  每个城市最多 3 张照片
/// - `manifest.json`    版本号 / 导出时间 / 条数，只给人看，恢复时可有可无
///
/// 之所以用 zip + 纯本地文件：这个 App 没有账号、没有云，数据只在这台手机上。
/// 换机、重装、误清空之后，唯一能把「去过的地方」找回来的方法就是一个能自己拿在手里的文件。
@MainActor
final class BackupService {
    static let shared = BackupService()

    /// 备份包的信息，界面用它显示「这份包里有什么」
    struct Summary: Equatable {
        var cityCount: Int = 0
        var pendingCount: Int = 0
        var photoCount: Int = 0
        var bytes: Int = 0
        var createdAt: Date?

        var sizeText: String {
            if bytes >= 1024 * 1024 {
                return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
            }
            if bytes >= 1024 { return "\(bytes / 1024) KB" }
            return "\(bytes) B"
        }

        var contentsText: String {
            var parts = ["\(cityCount) 个城市", "\(photoCount) 张照片"]
            if pendingCount > 0 { parts.append("\(pendingCount) 个待确认") }
            parts.append(sizeText)
            return parts.joined(separator: " · ")
        }
    }

    enum BackupError: LocalizedError {
        case missingData
        case emptyBackup

        var errorDescription: String? {
            switch self {
            case .missingData: return "包里没有找到 footprint.json，这可能不是足迹地球的备份"
            case .emptyBackup: return "现在还没有记录，先在地球上点亮几个城市吧"
            }
        }
    }

    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "backup")
    private let fm = FileManager.default

    /// 自动备份落在这里：App 沙盒的 Documents/Backups（开启文件共享后能在「文件」里看到）
    private(set) lazy var directory: URL = {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// 自动保留最近几份，避免越攒越多
    static let keepCount = 5

    private init() {}

    // MARK: - 备份

    /// 打一个备份包，返回文件地址。同时会顺手清掉太旧的几份。
    @discardableResult
    func makeBackup(store: VisitStore, trips: TripStore? = nil) throws -> URL {
        guard store.visits.values.contains(where: { $0.status == .visited }) else {
            throw BackupError.emptyBackup
        }

        var entries: [ZipArchive.Entry] = []
        let json = try store.exportData()
        entries.append(.init(name: "footprint.json", data: json))

        // 家和出行单独存一份，恢复时一起带回来
        if let travel = trips?.exportData() {
            entries.append(.init(name: "travel.json", data: travel))
        }

        let referenced = Set(store.visits.values.flatMap { $0.photos })
        var packedPhotos = 0
        for name in referenced.sorted() {
            let url = PhotoStore.shared.directoryURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            entries.append(.init(name: "photos/\(name)", data: data))
            packedPhotos += 1
        }

        let manifest = Manifest(
            app: appVersion,
            createdAt: Date(),
            cityCount: store.visits.values.filter { $0.status == .visited }.count,
            pendingCount: store.pendings.count,
            photoCount: packedPhotos
        )
        if let data = try? JSONEncoder().encode(manifest) {
            entries.append(.init(name: "manifest.json", data: data))
        }

        let archive = ZipArchive.make(entries)
        let url = directory.appendingPathComponent(fileName(for: Date()))
        try archive.write(to: url, options: .atomic)
        log.info("backup written: \(url.lastPathComponent), \(archive.count) bytes")
        pruneOldBackups()
        return url
    }

    /// 已有的备份，新的排前面
    func existingBackups() -> [URL] {
        let items = (try? fm.contentsOfDirectory(at: directory,
                                                includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - 恢复

    /// 先看包里有什么，不动本地数据（恢复前的确认弹窗用）
    func inspect(_ url: URL) throws -> Summary {
        let entries = try readEntries(at: url)
        guard let jsonEntry = dataEntry(named: "footprint.json", in: entries) else {
            throw BackupError.missingData
        }
        let snapshot = try decodeSnapshot(jsonEntry.data)
        var summary = Summary()
        summary.cityCount = snapshot.cities
        summary.pendingCount = snapshot.pendings
        summary.photoCount = entries.filter { $0.name.hasPrefix("photos/") && !$0.name.hasSuffix("/") }.count
        summary.bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if let manifest = dataEntry(named: "manifest.json", in: entries),
           let info = try? JSONDecoder().decode(Manifest.self, from: manifest.data) {
            summary.createdAt = info.createdAt
        } else {
            summary.createdAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
        return summary
    }

    /// 用备份包整体覆盖本地数据（记录 + 照片）。调用前请务必让用户确认过。
    @discardableResult
    func restore(from url: URL, store: VisitStore, trips: TripStore? = nil) throws -> Summary {
        let entries = try readEntries(at: url)
        guard let jsonEntry = dataEntry(named: "footprint.json", in: entries) else {
            throw BackupError.missingData
        }

        // 先把 JSON 读通，确认是可用的包，再动手改本地数据
        let counts = try store.importData(jsonEntry.data)

        // 老备份包里没有 travel.json，那就保持现在的家与行程不动
        if let travel = dataEntry(named: "travel.json", in: entries) {
            trips?.importData(travel.data)
        }

        let photos = entries.filter { $0.name.hasPrefix("photos/") && !$0.name.hasSuffix("/") }
        PhotoStore.shared.clearAll()
        var restoredPhotos = 0
        for entry in photos {
            let name = String(entry.name.dropFirst("photos/".count))
            if PhotoStore.shared.writeRaw(entry.data, as: name) { restoredPhotos += 1 }
        }

        var summary = Summary()
        summary.cityCount = counts.cities
        summary.pendingCount = counts.pendings
        summary.photoCount = restoredPhotos
        summary.bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        summary.createdAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        log.info("restored \(counts.cities) cities, \(restoredPhotos) photos from \(url.lastPathComponent)")
        return summary
    }

    /// 读一个外部文件（从「文件」App 选进来的）。自动处理安全作用域。
    func readExternal(_ url: URL) throws -> [ZipArchive.Entry] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try ZipArchive.read(try Data(contentsOf: url))
    }

    // MARK: - 内部

    private struct Manifest: Codable {
        var app: String
        var createdAt: Date
        var cityCount: Int
        var pendingCount: Int
        var photoCount: Int
    }

    private func readEntries(at url: URL) throws -> [ZipArchive.Entry] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try ZipArchive.read(try Data(contentsOf: url))
    }

    /// 允许包里的 json 在子目录下（有人会把文件先放进文件夹再压缩）
    private func dataEntry(named name: String, in entries: [ZipArchive.Entry]) -> ZipArchive.Entry? {
        entries.first { $0.name == name }
            ?? entries.first { $0.name.hasSuffix("/" + name) }
    }

    private func decodeSnapshot(_ data: Data) throws -> (cities: Int, pendings: Int) {
        struct Probe: Decodable {
            struct Item: Decodable { var status: String? }
            var visits: [Item]
            var pendings: [Item]
        }
        let probe = try JSONDecoder().decode(Probe.self, from: data)
        return (probe.visits.filter { $0.status == nil || $0.status == "visited" }.count,
                probe.pendings.count)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.4.0"
        let build = info?["CFBundleVersion"] as? String ?? "4"
        return "\(short) (\(build))"
    }

    private func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "足迹地球-备份-\(formatter.string(from: date)).zip"
    }

    private func pruneOldBackups() {
        let all = existingBackups()
        guard all.count > Self.keepCount else { return }
        for url in all.dropFirst(Self.keepCount) {
            try? fm.removeItem(at: url)
        }
    }
}
