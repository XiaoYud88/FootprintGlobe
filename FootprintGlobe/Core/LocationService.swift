import Foundation
import CoreLocation
import Combine

/// 定位服务封装。
///
/// 采样策略（受 iOS 限制，没有「定时轮询」这回事）：
/// - `startMonitoringSignificantLocationChanges()`：系统在「显著位移」时被动唤醒 App，
///   这是后台补点的主要来源，耗电极低；
/// - `requestLocation()`：App 进入前台/点「定位」时立刻取一次精确点；
/// - 拒绝授权或系统不唤醒时，用户在「待确认」里手动确认兜底。
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastError: String?

    /// 主线程回调
    var onUpdate: ((CLLocation) -> Void)?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    var needsPermissionPrompt: Bool {
        status == .notDetermined || status == .denied
    }

    func requestPermission() {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // 升级到「始终允许」，后台才能补点
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start() {
        requestPermission()
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
        if status == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    /// 主动取一次当前点（前台用）
    func refreshNow() {
        manager.requestLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = location
            self.lastError = nil
            self.onUpdate?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        if code == CLError.locationUnknown.rawValue { return }
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        DispatchQueue.main.async {
            self.status = newStatus
            if newStatus == .authorizedAlways {
                manager.allowsBackgroundLocationUpdates = true
                manager.startMonitoringSignificantLocationChanges()
            }
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}
