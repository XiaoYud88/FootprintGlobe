import Foundation
import Compression

/// 极简 ZIP 读写：只用来打包自己的备份，所以只实现「存储（不压缩）」写出，
/// 读取时同时支持存储和 deflate（别人用系统「压缩」出来的 zip 也能读）。
///
/// 不引第三方库的原因：备份功能必须永远能用，不能因为依赖某个包在某次升级后失效。
enum ZipArchive {
    struct Entry {
        let name: String
        let data: Data
    }

    enum ZipError: LocalizedError {
        case notZip
        case truncated
        case unsupportedMethod(UInt16)
        case inflateFailed(String)

        var errorDescription: String? {
            switch self {
            case .notZip: return "这不是一个 zip 文件"
            case .truncated: return "zip 文件不完整"
            case .unsupportedMethod(let m): return "不支持的压缩方式（\(m)）"
            case .inflateFailed(let name): return "解压失败：\(name)"
            }
        }
    }

    // MARK: - 写

    static func make(_ entries: [Entry]) -> Data {
        var payload = Data()
        var directory = Data()
        var offset = 0

        let (dosTime, dosDate) = dosStamp(Date())

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local.appendUInt32(0x0403_4B50)          // 本地文件头
            local.appendUInt16(20)                   // 需要的版本
            local.appendUInt16(0x0800)               // bit 11：文件名是 UTF-8
            local.appendUInt16(0)                    // 存储，不压缩
            local.appendUInt16(dosTime)
            local.appendUInt16(dosDate)
            local.appendUInt32(crc)
            local.appendUInt32(size)                 // 压缩后
            local.appendUInt32(size)                 // 原始
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)                    // 扩展字段
            local.append(nameData)
            local.append(entry.data)

            payload.append(local)

            directory.appendUInt32(0x0201_4B50)      // 中央目录
            directory.appendUInt16(20)               // 生成版本
            directory.appendUInt16(20)               // 需要的版本
            directory.appendUInt16(0x0800)
            directory.appendUInt16(0)
            directory.appendUInt16(dosTime)
            directory.appendUInt16(dosDate)
            directory.appendUInt32(crc)
            directory.appendUInt32(size)
            directory.appendUInt32(size)
            directory.appendUInt16(UInt16(nameData.count))
            directory.appendUInt16(0)                // 扩展
            directory.appendUInt16(0)                // 注释
            directory.appendUInt16(0)                // 起始磁盘
            directory.appendUInt16(0)                // 内部属性
            directory.appendUInt32(0)                // 外部属性
            directory.appendUInt32(UInt32(offset))
            directory.append(nameData)

            offset += local.count
        }

        var archive = payload
        archive.append(directory)

        archive.appendUInt32(0x0605_4B50)             // 中央目录结束
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(directory.count))
        archive.appendUInt32(UInt32(payload.count))
        archive.appendUInt16(0)
        return archive
    }

    // MARK: - 读

    static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { throw ZipError.notZip }

        // 从尾部往前找中央目录结束标记（注释最长 64KB，这里只看最后 4KB）
        var eocd = -1
        let lowerBound = max(0, bytes.count - 4096)
        var i = bytes.count - 22
        while i >= lowerBound {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }

        let count = Int(uint16(bytes, eocd + 10))
        let directorySize = Int(uint32(bytes, eocd + 12))
        let directoryOffset = Int(uint32(bytes, eocd + 16))
        guard directoryOffset + directorySize <= bytes.count else { throw ZipError.truncated }

        var entries: [Entry] = []
        var cursor = directoryOffset

        for _ in 0..<count {
            guard cursor + 46 <= bytes.count else { throw ZipError.truncated }
            guard uint32(bytes, cursor) == 0x0201_4B50 else { throw ZipError.notZip }

            let method = uint16(bytes, cursor + 10)
            let compressedSize = Int(uint32(bytes, cursor + 20))
            let uncompressedSize = Int(uint32(bytes, cursor + 24))
            let nameLength = Int(uint16(bytes, cursor + 28))
            let extraLength = Int(uint16(bytes, cursor + 30))
            let commentLength = Int(uint16(bytes, cursor + 32))
            let localOffset = Int(uint32(bytes, cursor + 42))

            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.truncated }
            let nameBytes = bytes[(cursor + 46)..<(cursor + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)

            // 文件夹条目（以 / 结尾）跳过
            if !name.hasSuffix("/") {
                guard localOffset + 30 <= bytes.count,
                      uint32(bytes, localOffset) == 0x0403_4B50 else { throw ZipError.truncated }
                let localNameLength = Int(uint16(bytes, localOffset + 26))
                let localExtraLength = Int(uint16(bytes, localOffset + 28))
                let start = localOffset + 30 + localNameLength + localExtraLength
                guard start + compressedSize <= bytes.count else { throw ZipError.truncated }
                let raw = Data(bytes[start..<(start + compressedSize)])

                switch method {
                case 0:
                    entries.append(Entry(name: name, data: raw))
                case 8:
                    guard let inflated = inflate(raw, expected: uncompressedSize) else {
                        throw ZipError.inflateFailed(name)
                    }
                    entries.append(Entry(name: name, data: inflated))
                default:
                    throw ZipError.unsupportedMethod(method)
                }
            }

            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - 底层

    private static func inflate(_ data: Data, expected: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = max(expected, 1024)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                guard let dstPointer = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcPointer = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstPointer, capacity,
                                                 srcPointer, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    /// MS-DOS 的时间戳格式（zip 规定的）
    private static func dosStamp(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // zip 的年份字段是从 1980 起的偏移量，7 位（0–127）
        let year = min(127, max(1980, c.year ?? 1980) - 1980)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | ((c.second ?? 0) / 2))
        let day = UInt16(year << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
