import Foundation
import UserNotifications
import OSLog

/// 本地到访提醒。
///
/// 触发点：定位状态机刚生成一个「候选」时（也就是你到了一个从没记录过的城市），
/// 立刻发一条本地通知「确认记录 太原市？」，点通知直接进待确认列表。
/// 完全本地，不发网络请求，也不需要推送证书。
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// 用户是否打开了「到访提醒」开关
    @Published var enabled: Bool
    /// 系统通知权限
    @Published private(set) var authorized = false
    /// 点通知进来的标记，界面消费掉之后置回 false
    @Published var openPendingRequest = false

    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "notify")
    private static let enabledKey = "notify.newPending"

    private override init() {
        enabled = UserDefaults.standard.object(forKey: NotificationService.enabledKey) as? Bool ?? false
        super.init()
    }

    /// 在 App 启动最早时机调用：注册代理 + 刷新权限状态
    func bootstrap() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorization() }
    }

    // MARK: - 权限

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let ok = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        await MainActor.run { self.authorized = ok }
    }

    /// 打开开关时请求权限；被拒绝则把开关回退并报错
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { self.authorized = granted }
            return granted
        } catch {
            log.error("request authorization failed: \(error.localizedDescription)")
            await MainActor.run { self.authorized = false }
            return false
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
    }

    // MARK: - 发送

    /// 新城市出现在候选里时调用。同一城市只发一次（用 code 做通知 id）。
    func notifyNewPending(cityName: String, code: String) {
        guard enabled else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            guard ok else { return }

            let content = UNMutableNotificationContent()
            content.title = "确认记录 \(cityName)？"
            content.body = "你在这里待了一会儿了。点一下进去填「第一次来的时间」和故事。"
            content.sound = .default
            content.userInfo = ["code": code]

            let request = UNNotificationRequest(identifier: "pending-\(code)",
                                                content: content,
                                                trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                log.info("notified pending \(code)")
            } catch {
                log.error("add notification failed: \(error.localizedDescription)")
            }
        }
    }

    func clearPendingNotification(code: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["pending-\(code)"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        // 在前台也弹出来，不然「到访提醒」等于没有
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if response.notification.request.content.userInfo["code"] != nil {
                self.openPendingRequest = true
            }
        }
    }
}
