import Foundation
import OSLog

/// 本地存储：已确认的到访 + 待确认候选。落盘为 Application Support 里的一个 JSON。
@MainActor
final class VisitStore: ObservableObject {
    @Published private(set) var visits: [String: Visit] = [:]
    @Published private(set) var pendings: [String: PendingVisit] = [:]

    private let fileURL: URL
    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "store")

    private struct Snapshot: Codable {
        var visits: [Visit]
        var pendings: [PendingVisit]
    }

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FootprintGlobe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("footprint.json")
        load()
    }

    // MARK: - 读取

    func isVisited(_ code: String) -> Bool {
        visits[code]?.status == .visited
    }

    func visit(_ code: String) -> Visit? { visits[code] }

    var visitedCodes: Set<String> {
        Set(visits.values.filter { $0.status == .visited }.map { $0.code })
    }

    var wishlistCodes: Set<String> {
        Set(visits.values.filter { $0.status == .wishlist }.map { $0.code })
    }

    var visitedProvinceCodes: Set<String> {
        Set(visits.values.filter { $0.status == .visited }.map { $0.provinceCode })
    }

    var sortedVisits: [Visit] {
        visits.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    var pendingList: [PendingVisit] {
        pendings.values.sorted { $0.firstSeen > $1.firstSeen }
    }

    var pendingCodes: Set<String> { Set(pendings.keys) }

    var cityCount: Int { visits.values.filter { $0.status == .visited }.count }

    var provinceCount: Int { visitedProvinceCodes.count }

    // MARK: - 写入

    @discardableResult
    func markVisited(_ region: Region, manual: Bool, at date: Date = Date()) -> Visit {
        var visit = visits[region.code] ?? Visit(code: region.code,
                                                cityName: region.name,
                                                provinceCode: region.provinceCode,
                                                status: .visited,
                                                firstSeen: date,
                                                lastSeen: date,
                                                dayCount: 1,
                                                sampleCount: 1,
                                                isManual: manual,
                                                note: "")
        visit.status = .visited
        visit.cityName = region.name
        visit.provinceCode = region.provinceCode
        visit.lastSeen = max(visit.lastSeen, date)
        if manual { visit.isManual = true }
        visits[region.code] = visit
        pendings.removeValue(forKey: region.code)
        save()
        return visit
    }

    func remove(code: String) {
        if let visit = visits[code] {
            for name in visit.photos { PhotoStore.shared.delete(name) }
        }
        visits.removeValue(forKey: code)
        save()
    }

    func toggle(code: String, region: Region) {
        if isVisited(code) { remove(code: code) }
        else { markVisited(region, manual: true) }
    }

    func setStatus(_ status: VisitStatus, for region: Region) {
        if var visit = visits[region.code] {
            visit.status = status
            visits[region.code] = visit
        } else {
            markVisited(region, manual: true)
            if var visit = visits[region.code] {
                visit.status = status
                visits[region.code] = visit
            }
        }
        save()
    }

    /// 已经在名单里的城市又来了一次：更新最后到访时间和天数。
    func touch(_ region: Region, at date: Date) {
        guard var visit = visits[region.code], visit.status == .visited else { return }
        let isNewDay = !Calendar.current.isDate(visit.lastSeen, inSameDayAs: date)
        visit.lastSeen = max(visit.lastSeen, date)
        visit.sampleCount += 1
        if isNewDay { visit.dayCount += 1 }
        visits[region.code] = visit
        save()
    }

    @discardableResult
    func upsertPending(_ region: Region, coord: GeoCoord, at date: Date) -> PendingVisit {
        var pending = pendings[region.code] ?? PendingVisit(code: region.code,
                                                           cityName: region.name,
                                                           provinceCode: region.provinceCode,
                                                           firstSeen: date,
                                                           lastSeen: date,
                                                           sampleCount: 0,
                                                           lastLon: coord.lon,
                                                           lastLat: coord.lat)
        pending.cityName = region.name
        pending.provinceCode = region.provinceCode
        pending.lastSeen = max(pending.lastSeen, date)
        pending.sampleCount += 1
        pending.lastLon = coord.lon
        pending.lastLat = coord.lat
        pendings[region.code] = pending
        save()
        return pending
    }

    @discardableResult
    func confirmPending(code: String, at date: Date = Date()) -> Visit? {
        guard let pending = pendings[code] else { return nil }
        pendings.removeValue(forKey: code)
        let days = Calendar.current.dateComponents([.day], from: pending.firstSeen, to: pending.lastSeen).day ?? 0
        let visit = Visit(code: pending.code,
                          cityName: pending.cityName,
                          provinceCode: pending.provinceCode,
                          status: .visited,
                          firstSeen: pending.firstSeen,
                          lastSeen: max(pending.lastSeen, date),
                          dayCount: max(1, days + 1),
                          sampleCount: pending.sampleCount,
                          isManual: false,
                          note: "")
        visits[code] = visit
        save()
        return visit
    }

    func discardPending(code: String) {
        pendings.removeValue(forKey: code)
        save()
    }

    func setNote(_ note: String, for code: String) {
        guard var visit = visits[code] else { return }
        visit.note = note
        visits[code] = visit
        save()
    }

    /// 手动添加 / 编辑一条记录：可以指定「第一次去的时间」，也可以写备注。
    /// 这是城市清单里点开表单后唯一的写入口——点了保存才算进「去过」。
    @discardableResult
    func saveRecord(_ region: Region, status: VisitStatus,
                    firstVisit: Date, note: String,
                    tags: [String] = [], rating: Int = 0,
                    photos: [String] = []) -> Visit {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var visit = visits[region.code] ?? Visit(code: region.code,
                                                cityName: region.name,
                                                provinceCode: region.provinceCode,
                                                status: status,
                                                firstSeen: firstVisit,
                                                lastSeen: firstVisit,
                                                dayCount: 1,
                                                sampleCount: 0,
                                                isManual: true,
                                                note: "")
        visit.cityName = region.name
        visit.provinceCode = region.provinceCode
        visit.status = status
        visit.firstSeen = firstVisit
        visit.lastSeen = max(visit.lastSeen, firstVisit)
        visit.note = trimmed
        visit.tags = tags
        visit.rating = min(max(rating, 0), 5)
        visit.photos = Array(photos.prefix(Theme.Layout.maxPhotosPerCity))
        visit.isManual = true
        visits[region.code] = visit
        if status == .visited {
            pendings.removeValue(forKey: region.code)
        }
        save()
        return visit
    }

    /// 标签 / 星级 / 照片的局部更新（记录面板里改完立刻生效，不用整条重存）
    func setTags(_ tags: [String], for code: String) {
        guard var visit = visits[code] else { return }
        visit.tags = tags
        visits[code] = visit
        save()
    }

    func setRating(_ rating: Int, for code: String) {
        guard var visit = visits[code] else { return }
        visit.rating = min(max(rating, 0), 5)
        visits[code] = visit
        save()
    }

    func setPhotos(_ photos: [String], for code: String) {
        guard var visit = visits[code] else { return }
        visit.photos = Array(photos.prefix(Theme.Layout.maxPhotosPerCity))
        visits[code] = visit
        save()
    }

    var photoCount: Int { visits.values.reduce(0) { $0 + $1.photoCount } }
    var taggedCount: Int { visits.values.filter { !$0.tags.isEmpty }.count }

    /// 所有用过的标签，按出现次数倒序，给筛选栏用
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for visit in visits.values {
            for tag in visit.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }.map { $0.key }
    }

    /// 有备注（故事）的城市数量
    var storyCount: Int { visits.values.filter { $0.hasNote }.count }

    /// 按「第一次到访时间」倒序，给以后的时间线用
    var timelineVisits: [Visit] {
        visits.values.filter { $0.status == .visited }
            .sorted { $0.firstSeen > $1.firstSeen }
    }

    func resetAll() {
        visits = [:]
        pendings = [:]
        save()
    }

    // MARK: - 备份 / 恢复

    /// 导出当前存档的原始 JSON（备份包里就是这一份）
    func exportData() throws -> Data {
        let snapshot = Snapshot(visits: Array(visits.values), pendings: Array(pendings.values))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// 用备份包里的 JSON 整体替换当前存档。返回城市数 / 候选数，方便界面回显。
    @discardableResult
    func importData(_ data: Data) throws -> (cities: Int, pendings: Int) {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        visits = snapshot.visits.reduce(into: [:]) { $0[$1.code] = $1 }
        pendings = snapshot.pendings.reduce(into: [:]) { $0[$1.code] = $1 }
        save()
        return (visits.count, pendings.count)
    }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            visits = snapshot.visits.reduce(into: [:]) { $0[$1.code] = $1 }
            pendings = snapshot.pendings.reduce(into: [:]) { $0[$1.code] = $1 }
            log.info("loaded \(self.visits.count) visits, \(self.pendings.count) pendings")
        } catch {
            log.error("load failed: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let snapshot = Snapshot(visits: Array(visits.values), pendings: Array(pendings.values))
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("save failed: \(error.localizedDescription)")
        }
    }
}
