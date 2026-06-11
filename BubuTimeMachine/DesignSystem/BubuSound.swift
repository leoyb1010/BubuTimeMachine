import AVFoundation

// MARK: - 声音设计（Wave §6.2）
/// 四个声音时刻的轻量播放器。原则：轻、可关、默认关。
/// - ambient category（不打断正在放的音乐）、跟随静音键；
/// - 设置「外观」卡组开关控制，默认关闭；
/// - 自录 ≤50KB caf，不引第三方。
@MainActor
enum BubuSound {
    /// 全局开关（默认关）。设置页绑定它。
    private static let enabledKey = "bubu.sound.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    enum Effect: String {
        case save = "sfx-save"
        case seal = "sfx-seal"
        case unlock = "sfx-unlock"
        case milestone = "sfx-milestone"
        case birthday = "sfx-birthday"
    }

    /// 保活播放器引用，避免播放中被释放。
    private static var players: [String: AVAudioPlayer] = [:]
    private static var sessionConfigured = false

    static func play(_ effect: Effect) {
        guard isEnabled else { return }
        configureSessionIfNeeded()
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.7
            player.prepareToPlay()
            player.play()
            players[effect.rawValue] = player
        } catch {
            // 播放失败静默：声音是锦上添花，绝不打扰。
        }
    }

    /// ambient：不打断他人音乐、跟随静音键。
    private static func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
