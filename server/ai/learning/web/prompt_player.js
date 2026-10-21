/** Only protected, same-origin material can appear in a family lesson. */
export function protectedMediaURL(value, origin = location.origin) {
  if (typeof value !== 'string' || !value) throw new Error('这段原声尚未准备好，请让家长核对素材。');
  const url = new URL(value, origin);
  if (url.origin !== origin || url.username || url.password || !url.pathname.startsWith('/learning/')) {
    throw new Error('素材地址无效，请重新加载课程。');
  }
  return url.href;
}

/** No TTS, no instruction playlist, and no answer fallback. */
export class PromptPlayer {
  constructor({ origin = location.origin, createAudio = url => new Audio(url), onState = () => {} } = {}) {
    this.origin = origin; this.createAudio = createAudio; this.onState = onState; this.audio = null;
  }
  stop() {
    if (this.audio) { this.audio.pause(); this.audio.currentTime = 0; }
    this.audio = null; this.onState('idle');
  }
  async playClip(clip, allowedRoles) {
    if (!clip || !allowedRoles.includes(clip.role)) throw new Error('原声角色不正确，请让家长重新核对。');
    const url = protectedMediaURL(clip.audio_url, this.origin);
    this.stop();
    const audio = this.createAudio(url); this.audio = audio;
    audio.addEventListener('ended', () => { if (this.audio === audio) this.onState('idle'); });
    audio.addEventListener('error', () => { if (this.audio === audio) this.onState('error'); });
    try { await audio.play(); this.onState('playing'); }
    catch (error) { this.stop(); throw new Error('原声暂时无法播放，请检查网络后再试。', {cause: error}); }
  }
  playPrompt(activity) { return this.playClip(activity.prompt, activity.kind === 'music' ? ['context'] : ['question', 'cue']); }
  playAnswer(activity) { return this.playClip(activity.answer, ['answer']); }
}
