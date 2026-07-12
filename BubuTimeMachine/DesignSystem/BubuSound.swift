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

    static func play(_ effect: Effect) {
        guard isEnabled else { return }
        configureSession()
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

    /// 每次播放前把会话确立为 ambient：不打断他人音乐、跟随静音键。
    /// 每次都设，避免语音播放器（AudioPlayer 用 .playback）留下的全局 category 泄漏进这些提示音，
    /// 把用户的音乐或静音键行为搞乱——「后播者定全局」的坑就此堵住。
    private static func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
