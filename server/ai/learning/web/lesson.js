import {el, button, uid} from './dom.js';
import {protectedMediaURL} from './prompt_player.js';

const kindLabels = {listen_choice:'听一听 · 找一找',color_choice:'听一听 · 选颜色',sort:'听一听 · 放一放',speak:'轮到你来说',music:'一起听 · 一起唱'};

/** A lesson uses confirmed server activities. It never synthesizes a question. */
export function openLesson({container, items, title, childId, player, saveAttempt, close, notify}) {
  let index = 0, disposed = false, generation = 0;
  const runId = uid();
  document.body.classList.add('is-learning');
  const exit = () => {disposed = true; player.stop(); document.body.classList.remove('is-learning'); close();};
  function render() {
    player.stop(); const currentGeneration = ++generation;
    const {activity:a,pack_id:packId} = items[index];
    let selected = null, busy = false, answered = false, assistance = false;
    const feedback = el('p',{class:'lesson-feedback',role:'status','aria-live':'polite'},'准备好了，就听听老师怎么说。');
    const next = button(index === items.length-1 ? '完成今天的活动' : '下一个小发现 →', advance, 'primary'); next.disabled = true;
    const stage = el('div',{class:`activity-stage kind-${a.kind}`});
    const hint = el('p',{class:'lesson-instruction'},a.instruction);
    let contextImage = null;
    if (a.prompt?.image_url && a.kind !== 'music') {
      try {
        const picture = el('img',{src:protectedMediaURL(a.prompt.image_url),alt:'老师提问时的画面'});
        picture.addEventListener('error',()=>{feedback.textContent='提问画面暂时没加载出来，请稍后重试或让家长检查。';});
        contextImage = el('figure',{class:'question-context'},picture,el('figcaption',{},'看着老师的画面，再听听问什么。'));
      } catch { feedback.textContent='提问画面地址无效，请让家长重新核对。'; }
    }
    const choiceColors = choice => (Array.isArray(choice.colors) && choice.colors.length ? choice.colors : [choice.color]).filter(color=>/^#[0-9a-f]{6}$/i.test(color || ''));

    async function play(answer = false) {
      try { if (answer) {assistance = true; await player.playAnswer(a);} else await player.playPrompt(a); }
      catch (error) {feedback.textContent = error.message;}
    }
    async function record(choice, note) {
      if (busy || disposed) return; busy = true;
      feedback.textContent = '正在保存这次小尝试…';
      try {
        const result = await saveAttempt({id:uid(),child_id:childId,pack_id:packId,activity_id:a.id,kind:a.kind,run_id:runId,...(choice ? {choice} : {}),assistance, ...(note ? {note} : {})});
        if (disposed || currentGeneration !== generation) return;
        answered = true; next.disabled = false;
        if (result.pending) {
          feedback.textContent = `已保存在这台设备，${result.pending} 条记录等待同步。${result.error?.status ? '请回到家长页处理连接或权限问题。' : '恢复网络后会再次同步。'}`;
        } else {
          feedback.textContent = choice ? (choice === a.correct_choice ? '找到了！还想再听一次也可以。' : '已经记下这次尝试。可以再听一次，换一个试试。') : '这次小尝试已经记下啦。';
        }
      } catch (error) {feedback.textContent = '这次记录没有保存成功，请保持页面打开并重试。'; notify(error.message);}
      finally {busy = false;}
    }
    function advance() {
      if (!answered || busy) return;
      if (index < items.length-1) {index++; render(); return;}
      player.stop();
      container.replaceChildren(el('section',{class:'lesson-finish'},el('span',{class:'finish-symbol','aria-hidden':'true'},'✦'),el('p',{class:'eyebrow'},'一起玩过，就是一个小发现'),el('h1',{},'今天先到这里吧'),el('p',{},'把刚才的小发现，带到生活里试一试。'),button('回到课程日历',exit,'primary')));
    }
    const audioControls = el('div',{class:'audio-controls'},button(a.kind === 'music' ? '▶ 听这段歌曲' : '▶ 听老师的题目',()=>play(false),'primary play-prompt'),button('停止播放',()=>player.stop(),'quiet'));
    if (a.answer) audioControls.append(button('听老师示范',()=>play(true),'secondary play-answer'));
    if (['listen_choice','color_choice','sort'].includes(a.kind)) {
      const choices = el('div',{class:'choices',role:'group','aria-label':'选择一个答案'});
      const basket = a.kind === 'sort' ? button('先选一个，再点这里放进篮子', async () => {if (selected) await record(selected);},'basket') : null;
      if (basket) basket.disabled = true;
      const colorPreview = a.kind === 'color_choice' ? el('div',{class:'color-selection','aria-live':'polite'},el('p',{},'选一组颜色，和老师的画面对照看看。')) : null;
      for (const choice of a.choices || []) {
        const choiceNode = button('',async () => {
          if (busy) return;
          selected = choice.id;
          for (const node of choices.children) node.setAttribute('aria-pressed',String(node === choiceNode));
          if (colorPreview) {
            const band=el('div',{class:'selected-color-band','aria-label':choice.label});
            for(const color of choiceColors(choice)){const part=el('span',{'aria-hidden':'true'});part.style.backgroundColor=color;band.append(part);}
            colorPreview.replaceChildren(el('p',{},`你选的颜色：${choice.label}`),band);
          }
          if (basket) {basket.disabled = false; basket.textContent = `把「${choice.label}」放进篮子 ↓`;}
          else await record(choice.id);
        },'choice');
        choiceNode.setAttribute('aria-pressed','false');
        if (choice.image_url) {
          try {const image = el('img',{src:protectedMediaURL(choice.image_url),alt:'',loading:'lazy'}); image.addEventListener('error',()=>{image.remove(); feedback.textContent='图片暂时没加载出来，可以重试，或请家长陪着看文字。';}); choiceNode.append(image);} catch {}
        }
        const colors=choiceColors(choice);
        if(colors.length){
          const group=el('span',{class:'swatch-group','aria-hidden':'true'});
          for(const color of colors){const swatch=el('span',{class:'swatch'});swatch.style.backgroundColor=color;group.append(swatch);}
          choiceNode.append(group);
        }
        choiceNode.append(el('span',{},choice.label)); choices.append(choiceNode);
      }
      if (colorPreview) stage.append(colorPreview); stage.append(choices); if(basket)stage.append(basket);
    } else if (a.kind === 'speak') {
      stage.append(...(contextImage ? [] : [el('div',{class:'speech-orbit','aria-hidden':'true'},'“ ”')]),el('p',{},'听完问题，说给身边的人听。'),button('我说好了',()=>record(null,'child_spoke'),'secondary'),button('今天先听一听',()=>{assistance=true;record(null,'listened_with_help');},'quiet'));
    } else if (a.kind === 'music') {
      let taps=0; const rhythm=button('♪ 跟着节奏拍一拍',()=>{taps++;rhythm.textContent=`♪ 拍了 ${taps} 下`;},'rhythm');
      stage.append(rhythm,el('p',{},'可以一起唱，也可以跟着做动作。'),button('我们听完啦',()=>record(null,'music_participated'),'secondary'));
    } else {stage.append(el('p',{},'这个活动暂不支持，请回到家长页重新生成。'));}
    container.replaceChildren(el('section',{class:'lesson'},el('div',{class:'lesson-top'},button('← 回到课程',exit,'quiet'),el('span',{},`${index+1} / ${items.length}`)),el('div',{class:'lesson-progress','aria-hidden':'true'},el('span',{style:`width:${(index+1)/items.length*100}%`})),el('p',{class:'eyebrow'},kindLabels[a.kind]||'互动活动'),el('h1',{tabindex:'-1'},a.title || title),hint,contextImage,audioControls,stage,feedback,el('div',{class:'lesson-bottom'},next)));
    container.querySelector('h1').focus({preventScroll:true});
    window.scrollTo(0,0);
  }
  render(); return exit;
}
