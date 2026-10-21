import {el,button,empty,dayString,shiftDay} from './dom.js';
import {api,AttemptQueue} from './api.js';
import {PromptPlayer} from './prompt_player.js';
import {sourcePanel,reviewPanel} from './review.js';
import {openLesson} from './lesson.js';

const main=document.querySelector('main'), account=document.querySelector('#account'), noticeNode=document.querySelector('#notice');
const query=new URLSearchParams(location.search);
const suppliedDate=query.get('date');
const state={context:null,child:null,date:/^\d{4}-\d{2}-\d{2}$/.test(suppliedDate || '') && !Number.isNaN(Date.parse(suppliedDate))?suppliedDate:dayString(),period:'day',queue:null,generation:0,inLesson:false};
const player=new PromptPlayer({onState:status=>{if(status==='error')notice('原声加载失败，请检查连接后重试。');}});
function notice(message){noticeNode.hidden=!message;noticeNode.textContent=message || '';}
function fail(error){
  if(error.status===401){state.generation++;state.inLesson=false;player.stop();state.context=null;state.queue=null;account.replaceChildren();login(error.message);}
  else if(error.status===409){notice(error.message);loadDay();}
  else notice(error.message || '连接暂时中断，请稍后重试。');
}
function queueMessage(result){
  if(!result.pending)return '本机的学习记录已同步。';
  if(result.error?.status===401)return `有 ${result.pending} 条记录等待同步，登录已过期，请重新登录。`;
  if(result.error?.status===403)return `有 ${result.pending} 条记录未同步：当前账号无权限，请联系家庭管理员。`;
  if(result.error?.status===409)return `有 ${result.pending} 条记录未同步：服务端记录冲突，请联系家庭管理员核查。`;
  return `有 ${result.pending} 条记录保存在这台设备，等待恢复连接后同步。`;
}
async function flush(){if(!state.queue)return;try{const result=await state.queue.flush();notice(queueMessage(result));}catch(error){notice('这台设备暂时无法保存记录，请检查浏览器存储空间。');}}
function login(message='') {
  document.body.classList.remove('is-learning');
  const identity=el('input',{name:'identity',autocomplete:'username',required:'',placeholder:'家庭账号'});
  const password=el('input',{name:'password',type:'password',autocomplete:'current-password',required:'',placeholder:'密码'});
  const submit=el('button',{type:'submit',class:'primary'},'打开家庭学习小屋');
  const form=el('form',{class:'login-form',onsubmit:async event=>{
    event.preventDefault();submit.disabled=true;
    try{await api('session',{method:'POST',body:{identity:identity.value.trim(),password:password.value}});password.value='';notice('');await boot();}
    catch(error){notice(error.message);}finally{submit.disabled=false;}
  }},el('p',{class:'eyebrow'},'家里人一起用'),el('h1',{},'欢迎回到学习小屋'),el('p',{},'使用布布时光机的家庭账号登录。课程与素材仅向家人开放。'),el('label',{class:'field'},'账号',identity),el('label',{class:'field'},'密码',password),submit);
  main.replaceChildren(form);notice(message);
}
async function boot(){
  main.replaceChildren(empty('正在连接家庭课程…','请稍等。'));
  try {
    state.context=await api('context');
    const children=state.context.children || [];
    state.child=children.find(x=>x.id===(state.child || query.get('child') || state.context.default_child))?.id || children[0]?.id;
    if(!state.child){main.replaceChildren(empty('还没有关联孩子','请先在布布时光机中建立孩子资料，再打开学习小屋。'));return;}
    state.queue=new AttemptQueue({userId:state.context.user.id,childId:state.child});
    renderAccount();await loadDay();if(state.queue.pending.length)await flush();
  }catch(error){if(error.status===401)login();else{main.replaceChildren(empty('暂时打不开学习小屋',error.message),button('重新连接',boot,'primary'));}}
}
function renderAccount(){
  const select=el('select',{'aria-label':'选择孩子',onchange:async event=>{player.stop();state.inLesson=false;state.child=event.target.value;state.queue=new AttemptQueue({userId:state.context.user.id,childId:state.child});notice('');await loadDay();if(state.queue.pending.length)flush();}});
  for(const child of state.context.children)select.append(el('option',{value:child.id,...(child.id===state.child?{selected:''}:{})},child.name));
  const logout=button('退出',async()=>{
    try{await api('session',{method:'DELETE'});player.stop();state.generation++;state.context=null;state.queue=null;account.replaceChildren();login();}catch(error){fail(error);}
  },'quiet');account.replaceChildren(select,logout);
}
function navigate(date,period=state.period){if(!date)return;state.date=date;state.period=period;state.inLesson=false;notice('');loadDay();}
function shell(){
  const name=state.context.children.find(x=>x.id===state.child)?.name || '宝贝';
  const date=el('input',{type:'date',value:state.date,'aria-label':'选择授课日期',onchange:event=>navigate(event.target.value)});
  const navigation=el('div',{class:'date-navigation'},button('‹',()=>navigate(shiftDay(state.date,-1)),'date-arrow'),date,button('›',()=>navigate(shiftDay(state.date,1)),'date-arrow'),button('今天',()=>navigate(dayString()),'quiet'));
  navigation.querySelectorAll('.date-arrow').forEach((node,i)=>node.setAttribute('aria-label',i?'后一天':'前一天'));
  const tabs=el('nav',{class:'period-tabs','aria-label':'学习与重温'});
  for(const [period,label] of [['day','按日期学'],['week','近 7 天重温'],['month','近 30 天重温']]){const tab=button(label,()=>navigate(state.date,period));tab.setAttribute('aria-current',state.period===period?'page':'false');tabs.append(tab);}
  const header=el('section',{class:'page-heading'},el('div',{},el('p',{class:'eyebrow'},'每天一点点 · 一起慢慢长大'),el('h1',{},`${name}，今天一起学`),el('p',{class:'intro'},'听老师的原声，把幼儿园的小发现玩一遍。')),navigation);
  const body=el('div',{id:'day-body','aria-busy':'true'},empty('正在找这一天的小发现…','正在读取已确认的课程。'));
  main.replaceChildren(header,tabs,body);return body;
}
async function loadDay(){
  document.body.classList.remove('is-learning');
  if(!state.context)return;
  state.inLesson=false;player.stop();const generation=++state.generation;const body=shell();
  const params=new URLSearchParams({child_id:state.child,date:state.date});
  try{
    if(state.period!=='day'){
      const review=await api(`reviews?${params}&period=${state.period}`);if(generation!==state.generation)return;renderReview(body,review);return;
    }
    const [packs,sources,days]=await Promise.all([api(`packs?${params}`),api(`sources?${params}`),api(`days?${new URLSearchParams({child_id:state.child,start:shiftDay(state.date,-3),end:shiftDay(state.date,3)})}`)]);
    if(generation!==state.generation)return;
    renderDay(body,packs.items || [],sources.items || [],days.days || []);
  }catch(error){if(generation!==state.generation)return;if(error.status===401){fail(error);return;}body.replaceChildren(empty(error.status===403?'暂时没有访问权限':'课程暂时没加载出来',error.message));if(error.status!==403)body.append(button('重新加载',loadDay,'primary'));}
  finally{body.setAttribute('aria-busy','false');}
}
function launch(items,title){
  if(!items.length)return;state.generation++;state.inLesson=true;notice('');
  const queue=state.queue;
  openLesson({container:main,items,title,childId:state.child,player,saveAttempt:attempt=>queue.add(attempt),close:loadDay,notify:notice});
}
function renderReview(body,data){
  const items=data.items || [];
  body.replaceChildren(el('p',{class:'window-label'},`${data.window_start} — ${data.window_end} · 只复习已经确认的活动`));
  if(!items.length){body.append(empty('这段时间还没有可重温的活动','先完成家长核对并发布课程。之后的小发现会按日期积累在这里。'));return;}
  body.append(el('section',{class:'review-start'},el('div',{},el('p',{class:'eyebrow'},state.period==='week'?'再见，老朋友':'这个月的小发现'),el('h2',{},`${items.length} 个熟悉的小活动`),el('p',{},'不用重新学一遍，挑熟悉的原声再玩一次。')),button('开始一起重温',()=>launch(items,'一起重温'),'primary')));
  for(const item of items)body.append(el('article',{class:'review-list-item'},el('div',{},el('h3',{},item.activity?.title || item.concept),el('p',{class:'muted'},item.reason || '已确认的学习内容')),button('只玩这个',()=>launch([item],item.activity.title),'secondary')));
}
function renderDay(body,packs,sources,days){
  const strip=el('nav',{class:'day-strip','aria-label':'附近日期'});
  for(let offset=-3;offset<=3;offset++){
    const date=shiftDay(state.date,offset), data=days.find(x=>x.date===date);
    const day=button('',()=>navigate(date));day.setAttribute('aria-current',date===state.date?'date':'false');
    day.append(el('small',{},new Date(`${date}T12:00:00`).toLocaleDateString('zh-CN',{weekday:'short'})),el('strong',{},String(Number(date.slice(-2)))),el('span',{class:data?.published_count?'has-lesson':'',title:data?.published_count?'有可玩的课程':''},data?.published_count?'可学':data?.source_count?'待整理':'—'));strip.append(day);
  }
  body.replaceChildren(strip);
  const sync=state.context.source_status || {};
  const syncButton=button('检查新素材',async()=>{
    syncButton.disabled=true;try{await api('sync',{method:'POST',body:{}});notice('已请求检查第二大脑的新素材，分析和编课需要一点时间。');}catch(error){fail(error);}finally{syncButton.disabled=false;}
  },'quiet');
  body.append(el('section',{class:'sync-strip'},el('div',{},el('strong',{},'第二大脑 · 自动整理中'),el('p',{class:'muted'},sync.error ? `最近同步未完成：${sync.error}` : sync.last_sync ? `上次同步：${new Date(sync.last_sync).toLocaleString('zh-CN')} · 教学材料来自「${state.context.school_inbox_display || '布布幼儿园'}」` : `等待「${state.context.school_inbox_display || '布布幼儿园'}」中的教学材料。`)),syncButton));
  if(!packs.length)body.append(empty('这一天还没有互动课程',sources.length?'素材已经收到。分析后会进入家长核对，确认题目和答案后孩子就能玩。':'把老师的教学材料放进「布布幼儿园」收件夹，第二大脑会自动分析。日常照片会进入时光，不会硬编成题目。'));
  for(const pack of packs){
    const activities=pack.payload?.activities || [],published=pack.status==='published';
    const statusLabel={published:'已核对 · 可以玩',draft:'待家长核对',no_lesson:'日常材料 · 无互动课程',revoked:'素材已改 · 需重新生成',superseded:'已有更新的课程',failed:'生成未完成',queued:'等待生成',processing:'正在生成'}[pack.status] || '等待整理';
    const card=el('article',{class:'pack-card'},el('div',{class:'pack-heading'},el('div',{},el('p',{class:'eyebrow'},`${pack.school_date} · ${activities.length} 个小活动`),el('h2',{},pack.title || pack.payload?.title || '这一天的小发现')),el('span',{class:`pill ${published?'ready':'pending'}`},statusLabel)));
    if(pack.status==='no_lesson')card.append(el('p',{class:'muted'},'这份材料没有可核对的教学目标，已作为日常记录保留。'));
    if(pack.status==='revoked')card.append(el('p',{class:'warning'},'原素材已校正，之前的课程暂停使用。请根据当前素材重新生成并核对。'));
    if(pack.payload?.summary)card.append(el('p',{class:'pack-summary'},pack.payload.summary));
    if(pack.payload?.warnings?.length)card.append(el('p',{class:'warning'},pack.payload.warnings.join('；')));
    const kinds={listen_choice:'听音找图',color_choice:'选颜色',sort:'放一放',speak:'说一说',music:'一起唱'};
    card.append(el('div',{class:'activity-chips'},activities.map(a=>el('span',{},kinds[a.kind] || a.kind))));
    if(published && activities.length)card.append(button('开始今天的小发现 →',()=>launch(activities.map(activity=>({pack_id:pack.id,activity})),pack.title),'primary start-lesson'));
    else if(!state.context.user.can_review)card.append(el('p',{class:'muted'},'等家长确认题目后，这里就可以开始啦。'));
    if(state.context.user.can_review){
      if(pack.status==='draft' && activities.length)card.append(reviewPanel(pack,{player,sources,reload:loadDay,fail,notice}));
      const regenerate=button('根据当前素材重新生成',async()=>{
        regenerate.disabled=true;try{await api(`packs/${encodeURIComponent(pack.id)}/regenerate`,{method:'POST',body:{}});notice('已请求重新生成。新课程需要重新核对，稍后点击刷新查看。');await loadDay();}catch(error){fail(error);}finally{regenerate.disabled=false;}
      },'quiet');
      card.append(el('details',{class:'manage-pack'},el('summary',{},'课程整理选项'),el('p',{class:'muted'},'转写校正或题目不合适时可重新生成。新版本需重新核对。'),regenerate));
    }
    body.append(card);
  }
  const original=el('details',{class:'sources'},el('summary',{},`素材与转写 · ${sources.length} 份`,el('span',{class:'muted'},'家长对照原片')));
  if(!sources.length)original.append(el('p',{},'这一天还没有已同步素材。'));
  for(const source of sources)original.append(sourcePanel(source,{canReview:state.context.user.can_review,reload:loadDay,fail,notice}));body.append(original);
  const refresh=button('刷新这一天',loadDay,'secondary');body.append(el('div',{class:'page-actions'},refresh,button('补传本机学习记录',flush,'quiet')));
}
window.addEventListener('online',()=>{if(state.queue)flush();});
window.addEventListener('pagehide',()=>player.stop());
boot();
