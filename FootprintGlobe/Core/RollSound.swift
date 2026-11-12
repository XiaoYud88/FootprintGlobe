import Foundation
import AVFoundation

/// 「转球」的声音：手指拖动地球时，一层极轻的低频摩擦声，速度越快越明显。
///
/// 不用任何音频素材：
/// 1. 现场生成 2 秒的噪声缓冲（白噪声 → 一阶低通 → 首尾交叉淡化，循环不会「啪」一下）；
/// 2. 串一个带通 EQ，把高频全部削掉，只留闷闷的「沙」；
/// 3. 音量跟着拖动速度走，停手就淡出。
///
/// 走 `.ambient` 分类：静音键拨下时自动静音，也不会打断用户正在听的音乐。
@MainActor
final class RollSound {
    static let shared = RollSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private var buffer: AVAudioPCMBuffer?
    private var running = false
    private var prepared = false

    /// 目标音量 + 是否有一个「追赶目标」的循环在跑
    private var targetVolume: Float = 0
    private var ramping = false

    static let enabledKey = "globe.rollSound"

    /// 默认开着，但音量极轻；不想要可以在「设置 → 地球」里关掉
    var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { end() }
        }
    }

    private init() {}

    /// 手指落下开始拖动
    func begin(intensity: Double) {
        guard enabled else { return }
        guard prepare() else { return }
        if !running {
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default,
                                                               options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
            } catch {
                return
            }
            player.play()
            running = true
        }
        apply(intensity)
    }

    /// 拖动过程中持续调用
    func update(intensity: Double) {
        guard running else { return }
        apply(intensity)
    }

    /// 松手
    func end() {
        guard running else { return }
        running = false
        ramp(to: 0)
        let engineRef = engine
        let playerRef = player
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !self.running else { return }
            playerRef.stop()
            engineRef.stop()
            try? AVAudioSession.sharedInstance().setActive(false,
                                                          options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: - 内部

    /// intensity: 0…1（拖动速度换算而来）
    private func apply(_ intensity: Double) {
        let value = min(1, max(0, intensity))
        // 上限只到 0.22：这是个背景音，不能盖过环境
        ramp(to: Float(0.022 + value * 0.20))
    }

    /// 主混音器没有 fadeDuration，这里用一个小循环把音量「追」到目标值。
    /// 拖动时每帧都会改目标，同一个循环会一直追下去，听起来是连续的。
    private func ramp(to value: Float) {
        targetVolume = value
        guard !ramping else { return }
        ramping = true
        Task { @MainActor in
            while true {
                let current = self.engine.mainMixerNode.outputVolume
                let next = current + (self.targetVolume - current) * 0.35
                if abs(self.targetVolume - next) < 0.0015 {
                    self.engine.mainMixerNode.outputVolume = self.targetVolume
                    break
                }
                self.engine.mainMixerNode.outputVolume = next
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            self.ramping = false
        }
    }

    private func prepare() -> Bool {
        if prepared { return true }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = makeNoise(format: format, seconds: 2.0) else { return false }

        engine.attach(player)
        engine.attach(eq)
        eq.bands[0].filterType = .lowPass
        eq.bands[0].frequency = 780
        eq.bands[0].bandwidth = 1.4
        eq.bands[0].gain = 6
        eq.bands[0].bypass = false

        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        // 从 0 开始，begin() 里再淡进来
        engine.mainMixerNode.outputVolume = 0

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        self.buffer = buffer
        prepared = true
        return true
    }

    /// 生成一段可以无缝循环的噪声：先做随机游走（低频更重），再做首尾交叉淡化。
    private func makeNoise(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let length = AVAudioFrameCount(sampleRate * seconds)
        let fade = AVAudioFrameCount(sampleRate * 0.12)
        let total = length + fade

        guard let raw = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let channel = raw.floatChannelData?[0] else { return nil }
        raw.frameLength = total

        var seed: UInt64 = 0x5EED_1234_ABCD
        var last = 0.0
        for index in 0..<Int(total) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let white = Double((seed >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(0x20_0000_0000_0000) - 0.5
            // 一阶低通：系数越小越闷，这里挑一个「像布料摩擦」的点
            last = last * 0.994 + white * 0.006
            channel[index] = Float(last * 26)
        }

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length),
              let dst = out.floatChannelData?[0] else { return nil }
        out.frameLength = length
        let fadeCount = Int(fade)
        for index in 0..<Int(length) {
            if index < fadeCount {
                let a = Float(index) / Float(fadeCount)
                dst[index] = channel[index] * a + channel[Int(length) + index] * (1 - a)
            } else {
                dst[index] = channel[index]
            }
        }
        return out
    }
}
