// MARK: - 声音设计（对照 iOS DesignSystem/BubuSound.swift，Wave §6.2）
// 四个声音时刻的轻量播放器。原则：轻、可关、默认关。
// iOS 用 AVAudioPlayer + .ambient session；HarmonyOS 用 @kit.AudioKit AVPlayer。
// NOTE: 这里给出可编译的等价实现：开关持久化到 preferences，播放走 media.AVPlayer
//       以 SoundEffect rawValue 命名解析 rawfile（resources/rawfile/<name>.ogg）。
//       若音频资源缺失或 API 不可用，播放静默失败——声音是锦上添花，绝不打扰。

import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';

export enum SoundEffect {
  save = 'sfx-save',
  seal = 'sfx-seal',
  unlock = 'sfx-unlock',
  milestone = 'sfx-milestone',
  birthday = 'sfx-birthday'
}

export class BubuSound {
  private static readonly storeName = 'bubu_sound';
  private static readonly enabledKey = 'bubu.sound.enabled';

  private static store: preferences.Preferences | null = null;
  private static enabled: boolean = false;

  // 在 Ability 启动时调用一次，回读全局开关。
  static initialize(context: common.UIAbilityContext): void {
    if (BubuSound.store) return;
    try {
      BubuSound.store = preferences.getPreferencesSync(context, { name: BubuSound.storeName });
      BubuSound.enabled = BubuSound.store.getSync(BubuSound.enabledKey, false) as boolean;
    } catch (e) {
      BubuSound.store = null;
    }
  }

  /// 全局开关（默认关）。设置页绑定它。
  static get isEnabled(): boolean { return BubuSound.enabled; }

  static set isEnabled(value: boolean) {
    BubuSound.enabled = value;
    const p = BubuSound.store;
    if (!p) return;
    try {
      p.putSync(BubuSound.enabledKey, value);
      p.flush();
    } catch (e) {
      // 静默
    }
  }

  /// 播放某个声音时刻（默认关时直接返回）。对照 iOS play(_:)。
  static play(effect: SoundEffect): void {
    if (!BubuSound.enabled) return;
    BubuSound.playRawfile(effect as string + '.ogg');
  }

  // NOTE: 以 AVPlayer 播放一次性短音效；用毕释放，避免泄漏。
  // ambient（不打断他人音乐、跟随静音）语义需配合 AudioSession，环境限制下从简。
  private static playRawfile(name: string): void {
    try {
      media.createAVPlayer().then((player: media.AVPlayer) => {
        player.on('stateChange', (state: string) => {
          if (state === 'initialized') {
            player.prepare();
          } else if (state === 'prepared') {
            player.play();
          } else if (state === 'completed') {
            player.release();
          }
        });
        // fdSrc / url 需指向 rawfile；具体资源加载方式视工程而定。
        player.url = 'rawfile://' + name;
      }).catch(() => {});
    } catch (e) {
      // 播放失败静默
    }
  }
}
