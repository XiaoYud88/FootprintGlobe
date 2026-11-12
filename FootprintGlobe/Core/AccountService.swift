import Foundation
import Combine
import UIKit
import CommonCrypto

/// 本机账号（M1-V3）。
///
/// 这一版**没有后台数据库**，账号完全留在这台手机上：
/// - 手机号 + 昵称 + 头像 → `Documents/account.json` + `Documents/Avatar/avatar.jpg`
/// - 密码 → 用随机盐做 PBKDF2-SHA256（12 万轮）后，把「盐 + 哈希」写进**钥匙串**
///   （`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`：只在本机、解锁后才读得到，
///   不会进 iCloud 备份，也不会被别的 App 读到）。
/// 所以哪怕有人把整个 App 目录拷走，拿到的也只是哈希，反推不出原密码；
/// 我们自己也不保存明文密码，忘记密码只能重设。
@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    struct LocalAccount: Codable, Equatable {
        var phone: String
        var nickname: String
        var createdAt: Date
        var avatarFile: String?

        /// 138****8888，界面上给别人看用这个
        var maskedPhone: String {
            guard phone.count == 11 else { return phone }
            return phone.prefix(3) + " **** " + phone.suffix(4)
        }
    }

    enum AccountError: LocalizedError {
        case invalidPhone
        case weakPassword
        case passwordMismatch
        case emptyNickname
        case alreadyRegistered
        case notRegistered
        case wrongPassword
        case missingCredential
        case storage(String)

        var errorDescription: String? {
            switch self {
            case .invalidPhone: return "手机号要 11 位，以 1 开头。"
            case .weakPassword: return "密码至少 6 位。"
            case .passwordMismatch: return "两次输入的密码不一样。"
            case .emptyNickname: return "昵称不能是空的。"
            case .alreadyRegistered: return "这台手机上已经有账号了，先退出登录再注册新的。"
            case .notRegistered: return "这个手机号还没注册过。"
            case .wrongPassword: return "密码不对。"
            case .missingCredential: return "这台手机上没有这个账号的密码记录（可能是恢复的数据），需要重新注册。"
            case .storage(let detail): return detail
            }
        }
    }

    // MARK: - 对外状态

    @Published private(set) var account: LocalAccount?
    @Published private(set) var avatar: UIImage?
    /// 注册完就自动登录；退出登录不影响已保存的档案
    @Published private(set) var signedIn = false

    var hasAccount: Bool { account != nil }

    /// 首页 / 护照页显示的名字：没账号就用「旅行者」
    var displayName: String {
        guard signedIn, let account, !account.nickname.isEmpty else { return "旅行者" }
        return account.nickname
    }

    /// 头像占位的第一个字
    var initial: String {
        String(displayName.prefix(1))
    }

    // MARK: - 存储位置

    private let keychainService = "com.footprintglobe.account"
    private let keychainAccount = "local-password"
    private let rounds = 120_000

    private init() {
        restore()
    }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var profileURL: URL { documents.appendingPathComponent("account.json") }

    private var avatarDirectory: URL { documents.appendingPathComponent("Avatar", isDirectory: true) }

    // MARK: - 注册 / 登录

    /// 手机号 + 密码直接注册：写完钥匙串就自动登录，昵称可以之后改
    func register(phone rawPhone: String, password: String,
                  confirm: String, nickname rawNickname: String) throws {
        let phone = rawPhone.filter(\.isNumber)
        guard phone.count == 11, phone.hasPrefix("1") else { throw AccountError.invalidPhone }
        guard password.count >= 6 else { throw AccountError.weakPassword }
        guard password == confirm else { throw AccountError.passwordMismatch }

        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "旅行者" + String(phone.suffix(4))
        let finalNickname = nickname.isEmpty ? fallback : nickname

        if let existing = loadProfile(), existing.phone != phone {
            throw AccountError.alreadyRegistered
        }

        // 已注册过同一个号：直接更新密码（相当于「重设密码」）
        try storeCredential(password: password, phone: phone)

        let account = LocalAccount(phone: phone,
                                   nickname: finalNickname,
                                   createdAt: loadProfile()?.createdAt ?? Date(),
                                   avatarFile: loadProfile()?.avatarFile)
        try writeProfile(account)
        self.account = account
        self.signedIn = true
        loadAvatar()
    }

    func signIn(phone rawPhone: String, password: String) throws {
        let phone = rawPhone.filter(\.isNumber)
        guard let stored = loadProfile() else { throw AccountError.notRegistered }
        guard stored.phone == phone else { throw AccountError.notRegistered }
        guard let credential = readCredential() else { throw AccountError.missingCredential }
        guard credential.phone == phone else { throw AccountError.notRegistered }
        guard let hash = Self.pbkdf2(password: password, salt: credential.salt,
                                     rounds: credential.rounds) else {
            throw AccountError.storage("密码校验失败，请重试。")
        }
        guard hash == credential.hash else { throw AccountError.wrongPassword }
        account = stored
        signedIn = true
        loadAvatar()
    }

    func signOut() {
        signedIn = false
    }

    /// 改昵称（头像另走 `saveAvatar`）
    func saveProfile(nickname rawNickname: String) throws {
        guard var account else { throw AccountError.notRegistered }
        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { throw AccountError.emptyNickname }
        account.nickname = String(nickname.prefix(16))
        try writeProfile(account)
        self.account = account
    }

    // MARK: - 头像

    func saveAvatar(_ image: UIImage) throws {
        guard var account else { throw AccountError.notRegistered }
        let name = "avatar.jpg"
        try FileManager.default.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        guard let data = Self.downscaled(image, maxSide: 512) else {
            throw AccountError.storage("这张图读不出来，换一张试试。")
        }
        do {
            try data.write(to: avatarDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw AccountError.storage("头像保存失败：\(error.localizedDescription)")
        }
        account.avatarFile = name
        try writeProfile(account)
        self.account = account
        avatar = image
    }

    func removeAvatar() {
        guard var account else { return }
        if let file = account.avatarFile {
            try? FileManager.default.removeItem(at: avatarDirectory.appendingPathComponent(file))
        }
        account.avatarFile = nil
        try? writeProfile(account)
        self.account = account
        avatar = nil
    }

    // MARK: - 档案读写

    private func restore() {
        account = loadProfile()
        // 有档案 + 有密码记录 = 上次是登录状态，直接恢复
        signedIn = (account != nil) && (readCredential() != nil)
        loadAvatar()
    }

    private func loadProfile() -> LocalAccount? {
        guard let data = try? Data(contentsOf: profileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalAccount.self, from: data)
    }

    private func writeProfile(_ account: LocalAccount) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(account).write(to: profileURL, options: .atomic)
        } catch {
            throw AccountError.storage("档案保存失败：\(error.localizedDescription)")
        }
    }

    private func loadAvatar() {
        guard let file = account?.avatarFile else { avatar = nil; return }
        let url = avatarDirectory.appendingPathComponent(file)
        avatar = UIImage(contentsOfFile: url.path)
    }

    // MARK: - 密码（钥匙串 + PBKDF2）

    private struct Credential: Codable {
        var phone: String
        var salt: Data
        var hash: Data
        var rounds: Int
        var algorithm: String
    }

    private func storeCredential(password: String, phone: String) throws {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, 16, base)
        }
        guard status == errSecSuccess else {
            throw AccountError.storage("生成随机盐失败。")
        }
        guard let hash = Self.pbkdf2(password: password, salt: salt, rounds: rounds) else {
            throw AccountError.storage("密码加密失败。")
        }
        let credential = Credential(phone: phone, salt: salt, hash: hash,
                                    rounds: rounds, algorithm: "pbkdf2-sha256")
        guard let payload = try? JSONEncoder().encode(credential) else {
            throw AccountError.storage("密码打包失败。")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = payload
        // 只在本机、解锁后才能读，不进 iCloud 备份
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AccountError.storage("密码写入钥匙串失败（\(addStatus)）。")
        }
    }

    private func readCredential() -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    /// PBKDF2-HMAC-SHA256：慢哈希，暴力试密码的成本很高
    nonisolated private static func pbkdf2(password: String, salt: Data, rounds: Int) -> Data? {
        var derived = Data(count: 32)
        let passwordLength = password.lengthOfBytes(using: .utf8)
        let result = derived.withUnsafeMutableBytes { derivedBuffer -> Int32 in
            guard let derivedBase = derivedBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCParamError)
            }
            return salt.withUnsafeBytes { saltBuffer -> Int32 in
                let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress
                return password.withCString { passwordPtr -> Int32 in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordPtr, passwordLength,
                                         saltBase, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                         UInt32(rounds),
                                         derivedBase, 32)
                }
            }
        }
        return result == Int32(kCCSuccess) ? derived : nil
    }

    // MARK: - 图片压缩

    nonisolated private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: 0.86)
    }
}
