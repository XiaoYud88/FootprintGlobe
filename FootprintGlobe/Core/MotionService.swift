import Foundation
import Combine
import CoreMotion

/// 陀螺仪视差（M1-V3 / 功能 17）。
///
/// 读重力方向而不是陀螺仪角速度：手机静止时角速度是 0，重力方向却一直跟着手腕走，
/// 正好适合做「轻轻转动手腕，地球跟着偏一点」的效果。
/// 输出是 -1…1 的倾斜量，真正偏多少度由 `AppModel.parallax` 决定，
/// 这样以后想调幅度只改一个系数，不用动这里。
@MainActor
final class MotionService: ObservableObject {
    /// 左右倾斜（-1 左 … 1 右）
    @Published private(set) var tiltX: Double = 0
    /// 前后倾斜（0 立着 … 1 快平放）
    @Published private(set) var tiltY: Double = 0
    /// 有没有真的拿到数据（模拟器 / 老设备没有陀螺仪时为 false，视差自动关掉）
    @Published private(set) var enabled = false

    private let manager = CMMotionManager()
    private var running = false
    /// 上一次发布的倾斜值，用来做过低通和「变化太小就不刷新」的节流
    private var lastX: Double = 0
    private var lastY: Double = 0

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let gravity = motion.gravity
            Task { @MainActor [weak self] in
                self?.ingest(gravity)
            }
        }
        enabled = true
    }

    func stop() {
        guard running else { return }
        manager.stopDeviceMotionUpdates()
        running = false
        enabled = false
        tiltX = 0
        tiltY = 0
    }

    private func ingest(_ gravity: CMAcceleration) {
        // 手机竖着拿：gravity ≈ (0, -1, 0)；平放着：gravity ≈ (0, 0, -1)
        let rawX = min(max(-gravity.x * 2.0, -1), 1)
        let rawY = min(max((gravity.y + 1.0) * 1.2, -1), 1)

        // 低通：让球是「跟着手慢慢偏」，而不是跟着传感器噪声抖
        let smoothedX = lastX * 0.82 + rawX * 0.18
        let smoothedY = lastY * 0.82 + rawY * 0.18

        // 变化小于阈值就不发通知，省掉无意义的整屏重绘
        guard abs(smoothedX - tiltX) > 0.012 || abs(smoothedY - tiltY) > 0.012 else { return }
        lastX = smoothedX
        lastY = smoothedY
        tiltX = smoothedX
        tiltY = smoothedY
    }
}
