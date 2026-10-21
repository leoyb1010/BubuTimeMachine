import {el,button} from './dom.js';
import {api} from './api.js';
import {protectedMediaURL} from './prompt_player.js';

export function sourcePanel(source, {canReview, reload, fail, notice}) {
  const details=el('details',{class:'source-card'},el('summary',{},source.name || '原始素材',el('span',{class:'pill'},({ready:'已分析',queued:'等待分析',processing:'分析中',failed:'分析未完成',unavailable:'暂不可用'})[source.state] || '待分析')));
  const original=el('div',{class:'source-original'});
  if(source.original_url) {
    try {
      const url=protectedMediaURL(source.original_url);
      if(source.kind === 'image' || source.mime?.startsWith('image/') || /\.(jpg|jpeg|png|webp)(\?|$)/i.test(url)) original.append(el('img',{src:url,alt:'老师提供的原始材料',loading:'lazy'}));
      else if(source.kind === 'audio' || source.mime?.startsWith('audio/')) original.append(el('audio',{src:url,controls:'',preload:'none','aria-label':'老师原音轨，供家长对照'}));
      else original.append(el('video',{src:url,controls:'',preload:'none',playsinline:'','aria-label':'老师原片，供家长对照'}));
    } catch {original.append(el('p',{},'原始材料地址无效，暂不能核对。'));}
  } else original.append(el('p',{},'原片还没有准备好，请稍后刷新。'));
  for(const media of original.querySelectorAll('video,audio,img')) media.addEventListener('error',()=>{ if(!original.querySelector('.warning')) original.append(el('p',{class:'warning'},'原始材料暂时无法加载。请检查连接并刷新，先不要确认这道题。')); });
  details.append(original);
  if(['failed','unavailable'].includes(source.state)) details.append(el('p',{class:'warning'},source.error || '素材分析尚未完成，请检查第二大脑同步状态后再刷新。'));
  const analysis=source.analysis || {};
  if(analysis.description)details.append(el('p',{},analysis.description));
  if(analysis.ocr)details.append(el('pre',{class:'ocr'},analysis.ocr));
  if(analysis.warnings?.length)details.append(el('p',{class:'warning'},analysis.warnings.join('；')));
  const segments=analysis.segments || [];
  if(!canReview || !segments.length) return details;
  const editor=el('details',{class:'transcript-editor'},el('summary',{},'原声转写或日期有误？核对后校正'));
  const fields=[];
  for(const segment of segments) {
    const start=el('input',{type:'number',min:'0',step:'0.1',value:segment.start,'aria-label':`${segment.id} 起始秒`});
    const end=el('input',{type:'number',min:'0',step:'0.1',value:segment.end,'aria-label':`${segment.id} 结束秒`});
    const text=el('textarea',{rows:'2','aria-label':`${segment.id} 转写文字`},segment.text);
    fields.push({segment,start,end,text}); editor.append(el('div',{class:'segment-row'},el('span',{},segment.id),el('label',{},'起始秒',start),el('label',{},'结束秒',end),el('label',{class:'segment-text'},'原声转写',text)));
  }
  const date=el('input',{type:'date',value:source.school_date,readonly:'','aria-label':'课程上课日期'});
  const checked=el('input',{type:'checkbox'});
  const save=button('保存校正，重新核对课程',async()=>{
    if(!checked.checked){notice('请先对照原片确认转写与授课日期。');return;}
    const updated=fields.map(({segment,start,end,text})=>({id:segment.id,start:Number(start.value),end:Number(end.value),text:text.value.trim()}));
    if(!date.value || updated.some(x=>!x.text || !Number.isFinite(x.start+x.end) || x.start<0 || x.end<=x.start)){notice('请填写日期，并检查每段的文字及起止秒数。');return;}
    save.disabled=true;
    try {await api(`sources/${encodeURIComponent(source.id)}/segments`,{method:'PATCH',body:{revision:source.revision ?? analysis.revision,segments:updated,school_date:date.value,date_confirmed:true}});notice('校正已保存，旧确认已失效。请重新生成并核对课程。');await reload();}
    catch(error){fail(error);}finally{save.disabled=false;}
  },'secondary');
  editor.append(el('label',{class:'field'},'授课日期',date),el('label',{class:'check-label'},checked,'我已对照原片核实上述转写和日期'),el('p',{class:'muted'},'校正会使依赖此素材的旧确认失效。系统不会把改写的文字当成老师原声。'),save);details.append(editor);return details;
}

export function reviewPanel(pack,{player,sources,reload,fail,notice}) {
  const activities=pack.payload?.activities || [];
  const panel=el('details',{class:'review-panel'},el('summary',{},'家长核对题目与答案',el('span',{class:'muted'},`版本 ${pack.revision}`)));
  panel.append(el('p',{},'每道题先听老师的问题，再单独听答案。对照原片、选项与授课日期，确认后孩子才能开始。'));
  const checks=[];
  for(const a of activities) {
    const digest=a.review_digest || (pack.confirmations || []).find(x=>x.activity_id===a.id)?.digest;
    const check=el('input',{type:'checkbox',disabled:!digest});
    const card=el('article',{class:'review-activity'},el('h3',{},a.title),el('p',{class:'muted'},a.instruction));
    const play=async(answer)=>{try{await (answer ? player.playAnswer(a) : player.playPrompt(a));}catch(error){notice(error.message);}};
    card.append(el('div',{class:'clip-row'},el('strong',{},a.kind==='music'?'歌曲片段':'老师的问题'),el('p',{},a.prompt?.text || '缺少转写'),el('small',{},`${a.prompt?.start ?? '?'}–${a.prompt?.end ?? '?'} 秒`),button(a.kind==='music'?'听歌曲原声':'听题目原声',()=>play(false),'secondary')));
    if(a.prompt?.image_url){
      try{card.append(el('figure',{class:'question-context review-context'},el('img',{src:protectedMediaURL(a.prompt.image_url),alt:'老师提问时的画面',loading:'lazy'}),el('figcaption',{},'问题对应的原片画面，请核对指物是否明确。')));}catch{card.append(el('p',{class:'warning'},'提问画面地址无效，暂不要确认。'));}
    }
    if(a.answer)card.append(el('div',{class:'clip-row answer-row'},el('strong',{},'示范答案'),el('p',{},a.answer.text),button('单独听答案',()=>play(true),'quiet')));
    if(a.choices?.length)card.append(el('p',{},`选项：${a.choices.map(x=>x.label).join(' / ')}；正确项：${a.choices.find(x=>x.id===a.correct_choice)?.label || '未提供'}`));
    const source=sources.find(x=>x.id===a.prompt?.source_id);
    card.append(el('p',{class:'muted'},`来源：${source?.name || a.prompt?.source_id || '未关联'} · 请在下方「素材与转写」对照原片。`));
    const exclude=button('这道题不合适，移除',async()=>{
      exclude.disabled=true;try{await api(`packs/${encodeURIComponent(pack.id)}/exclude`,{method:'POST',body:{revision:pack.revision,activity_id:a.id}});notice('已移除，课程版本已更新，请重新核对剩余题目。');await reload();}catch(error){fail(error);}finally{exclude.disabled=false;}
    },'danger-text');
    card.append(el('label',{class:'check-label'},check,a.kind==='music'?'歌曲片段与内容对应，可以一起唱':'问题原声、选项与答案一一对应'),exclude);
    if(!digest)card.append(el('p',{class:'warning'},'服务端未提供核对摘要，暂不能发布，请重新加载。'));
    checks.push({check,activity_id:a.id,digest});panel.append(card);
  }
  const dateChecked=el('input',{type:'checkbox'});
  const publish=button('确认并开放给孩子',async()=>{
    if(!dateChecked.checked || !checks.length || checks.some(x=>!x.check.checked || !x.digest)){notice('请逐道核对并勾选，同时确认授课日期。');return;}
    publish.disabled=true;
    try{await api(`packs/${encodeURIComponent(pack.id)}/publish`,{method:'POST',body:{revision:pack.revision,confirmations:checks.map(({activity_id,digest})=>({activity_id,digest,verified:true})),date_confirmed:true}});notice('已发布，孩子现在可以开始互动课程。');await reload();}catch(error){fail(error);}finally{publish.disabled=false;}
  },'primary');
  panel.append(el('label',{class:'check-label'},dateChecked,`授课日期确认为 ${pack.school_date}`),publish);
  return panel;
}
