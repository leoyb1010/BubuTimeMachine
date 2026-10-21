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
  const date=el('input',{type:'date',value:state.date,'aria-label':'选择上课日期',onchange:event=>navigate(event.target.value)});
  const navigation=el('div',{class:'date-navigation'},button('‹',()=>navigate(shiftDay(state.date,-1)),'date-arrow'),date,button('›',()=>navigate(shiftDay(state.date,1)),'date-arrow'),button('今天',()=>navigate(dayString()),'quiet'));
  navigation.querySelectorAll('.date-arrow').forEach((node,i)=>node.setAttribute('aria-label',i?'后一天':'前一天'));
  const tabs=el('nav',{class:'period-tabs','aria-label':'学习与复习'});
  for(const [period,label] of [['day','按日期学'],['week','本周复习'],['month','本月复习']]){const tab=button(label,()=>navigate(state.date,period));tab.setAttribute('aria-current',state.period===period?'page':'false');tabs.append(tab);}
  const header=el('section',{class:'page-heading'},el('div',{},el('p',{class:'eyebrow'},'每日学习'),el('h1',{},`${name}的每日学习`),el('p',{class:'intro'},'家长上传幼儿园课程视频，核对老师原声后，就可以一起玩。')),navigation);
  const body=el('div',{id:'day-body','aria-busy':'true'},empty('正在找这一天的课程…','请稍等。'));
  main.replaceChildren(header,tabs,body);return body;
}
async function loadDay(){
  document.body.classList.remove('is-learning');
  if(!state.context)return;
  clearTimeout(state.refreshTimer);
  state.inLesson=false;player.stop();const generation=++state.generation;const body=shell();
  const params=new URLSearchParams({child_id:state.child,date:state.date});
  try{
    if(state.period!=='day'){
      const review=await api(`reviews?${params}&period=${state.period}`);if(generation!==state.generation)return;renderReview(body,review);return;
    }
    const range=new URLSearchParams({child_id:state.child,start:shiftDay(state.date,-3),end:shiftDay(state.date,3)});
    const [list,days]=await Promise.all([api(`courses?${new URLSearchParams({child_id:state.child,start:state.date,end:state.date})}`),api(`days?${range}`)]);
    const courses=await Promise.all((list.items || []).map(course=>api(`courses/${encodeURIComponent(course.id)}`)));
    if(generation!==state.generation)return;
    renderDay(body,courses,days.days || []);
    if(courses.some(course=>course.state==='processing'))state.refreshTimer=setTimeout(()=>{if(generation===state.generation && !state.inLesson)loadDay();},8000);
  }catch(error){if(generation!==state.generation)return;if(error.status===401){fail(error);return;}body.replaceChildren(empty(error.status===403?'暂时没有访问权限':'课程暂时没加载出来',error.message));if(error.status!==403)body.append(button('重新加载',loadDay,'primary'));}
  finally{body.setAttribute('aria-busy','false');}
}
function launch(items,title){
  if(!items.length)return;state.generation++;state.inLesson=true;notice('');clearTimeout(state.refreshTimer);
  const queue=state.queue;
  openLesson({container:main,items,title,childId:state.child,player,saveAttempt:attempt=>queue.add(attempt),close:loadDay,notify:notice});
}
function renderReview(body,data){
  const items=data.items || [];
  body.replaceChildren(el('p',{class:'window-label'},`${data.window_start} — ${data.window_end} · 只复习家长已开放的课程`));
  if(!items.length){body.append(empty('这段时间还没有可复习的内容','家长上传课程并核对开放后，会按日期积累在这里。'));return;}
  body.append(el('section',{class:'review-start'},el('div',{},el('p',{class:'eyebrow'},state.period==='week'?'本周复习':'本月复习'),el('h2',{},`${items.length} 段老师原声`),el('p',{},'挑出还没玩过、或上次需要提示的内容，再玩一次。')),button('开始复习',()=>launch(items,'一起复习'),'primary')));
  for(const item of items)body.append(el('article',{class:'review-list-item'},el('div',{},el('h3',{},item.activity?.title || item.concept),el('p',{class:'muted'},item.reason || '已开放的学习内容')),button('只玩这个',()=>launch([item],item.activity.title),'secondary')));
}
const KIND_LABELS={teaching:'教学',practice:'练习',song:'儿歌'};
const STATE_LABELS={processing:'解析中',uploading:'上传未完成',draft:'待家长核对',published:'可以一起学',no_lesson:'没找到原声题',failed:'解析失败',waiting:'准备中'};
function uploadForm(){
  const title=el('input',{name:'title',required:'',maxlength:'60',placeholder:'例如：水果单词'});
  const kind=el('select',{name:'kind'},...Object.entries(KIND_LABELS).map(([value,label])=>el('option',{value},label)));
  const language=el('select',{name:'language'},el('option',{value:'en-US'},'英文'),el('option',{value:'zh-CN'},'中文'));
  const files=el('input',{type:'file',name:'files',multiple:'',required:'',accept:'video/*,audio/*,image/jpeg,image/png,image/heic'});
  const progress=el('progress',{max:'100',value:'0',hidden:true});
  const submit=el('button',{type:'submit',class:'primary'},'上传并开始解析');
  const form=el('form',{class:'upload-form',onsubmit:async event=>{
    event.preventDefault();
    const chosen=[...files.files].sort((a,b)=>Number(a.type.startsWith('image/'))-Number(b.type.startsWith('image/')));
    if(!title.value.trim()||!chosen.length){notice('请填写课程名称并选择文件。');return;}
    if(chosen.length>8){notice('每节课最多 8 个文件。');return;}
    if(!/^(video|audio)\//.test(chosen[0].type)){notice('至少需要一段有老师声音的视频或录音。');return;}
    // The family service sits behind a proxy that caps each request at about 100 MB.
    const large=chosen.find(file=>file.size>92*1024*1024);
    if(large){notice(`「${large.name}」超过 90 MB。请用布布时光机 App 上传（会自动压缩），或先剪成几段。`);return;}
    const send=(path,fields,file,field)=>new Promise((resolve,reject)=>{
      const data=new FormData();for(const [key,value] of fields)data.append(key,value);data.append(field,file,file.name);
      const request=new XMLHttpRequest();
      request.open('POST',`/learning/api/${path}`);request.setRequestHeader('X-Bubu-Learning','1');request.withCredentials=true;
      request.upload.onprogress=e=>{if(e.lengthComputable){progress.hidden=false;progress.value=Math.round(e.loaded/e.total*100);}};
      request.onload=()=>request.status>=200&&request.status<300?resolve(JSON.parse(request.responseText)):reject({status:request.status});
      request.onerror=()=>reject({status:0});request.send(data);
    });
    submit.disabled=true;
    try{
      notice(chosen.length>1?`正在上传第 1/${chosen.length} 个文件…`:'正在上传…');
      const course=await send('courses',[['child_id',state.child],['school_date',state.date],['title',title.value.trim()],['kind',kind.value],['language',language.value],['total_files',String(chosen.length)]],chosen[0],'files');
      for(let index=1;index<chosen.length;index++){notice(`正在上传第 ${index+1}/${chosen.length} 个文件…`);await send(`courses/${encodeURIComponent(course.id)}/files`,[],chosen[index],'file');}
      notice('已上传，正在解析老师原声。几分钟后会出现在下面。');loadDay();
    }catch(error){
      if(error.status===401)fail({status:401,message:'登录已过期，请重新登录。'});
      else if(error.status===413)notice('文件太大了，请先剪短后再上传。');
      else notice('上传没有完成，请检查网络后重试。如果课程显示“上传未完成”，删除后重新上传即可。');
    }finally{submit.disabled=false;progress.hidden=true;}
  }},el('label',{class:'field'},'课程名称',title),el('div',{class:'field-row'},el('label',{class:'field'},'课程类型',kind),el('label',{class:'field'},'老师讲的语言',language)),el('label',{class:'field'},'课程视频、录音或教具照片（最多 8 个）',files),el('p',{class:'muted'},`上课日期：${state.date}。一次上传就是一节课；素材只用于每日学习，不进入时光。`),progress,submit);
  return el('details',{class:'upload-card'},el('summary',{},'＋ 上传这一天的课程'),form);
}
function renderDay(body,courses,days){
  const strip=el('nav',{class:'day-strip','aria-label':'附近日期'});
  for(let offset=-3;offset<=3;offset++){
    const date=shiftDay(state.date,offset), data=days.find(x=>x.date===date);
    const day=button('',()=>navigate(date));day.setAttribute('aria-current',date===state.date?'date':'false');
    day.append(el('small',{},new Date(`${date}T12:00:00`).toLocaleDateString('zh-CN',{weekday:'short'})),el('strong',{},String(Number(date.slice(-2)))),el('span',{class:data?.published_count?'has-lesson':''},data?.published_count?'可学':data?.course_count?'整理中':'—'));strip.append(day);
  }
  body.replaceChildren(strip);
  const canReview=state.context.user.can_review;
  if(canReview)body.append(uploadForm());
  if(!courses.length)body.append(empty('这一天还没有课程',canReview?'点上面的「上传这一天的课程」，选老师的课堂视频。':'等家长上传并核对后，这里就可以开始啦。'));
  for(const course of courses){
    const pack=course.pack, activities=pack?.payload?.activities || [];
    const card=el('article',{class:'pack-card'},el('div',{class:'pack-heading'},el('div',{},el('p',{class:'eyebrow'},`${course.school_date} · ${KIND_LABELS[course.kind]||'课程'} · ${course.source_count} 个文件`),el('h2',{},course.title)),el('span',{class:`pill state-${course.state}`},STATE_LABELS[course.state]||course.state)));
    if(course.state==='processing')card.append(el('p',{class:'muted'},'家里的服务器正在完整听老师原声、看课堂画面。几分钟后自动刷新。'));
    if(course.state==='failed')card.append(el('p',{class:'warning'},'素材没能完整解析，可以删除后重新上传原片。'));
    if(course.state==='uploading')card.append(el('p',{class:'warning'},`只收到 ${course.source_count}/${course.expected_files} 个文件，上传中途断开了。请删除后重新上传。`));
    if(course.state==='no_lesson')card.append(el('p',{class:'muted'},pack?.payload?.summary || '没有找到可核对的老师原声。'));
    if(course.state==='waiting')card.append(el('p',{class:'muted'},'等家长核对后，这里就可以开始啦。'));
    if(activities.length){
      const kinds={listen_choice:'听音找图',color_choice:'选颜色',sort:'放一放',speak:'说一说',music:'一起唱'};
      card.append(el('div',{class:'activity-chips'},activities.map(a=>el('span',{},kinds[a.kind] || a.kind))));
    }
    if(course.state==='published'&&activities.length)card.append(button('开始一起学 →',()=>launch(activities.map(activity=>({pack_id:pack.id,activity})),course.title),'primary start-lesson'));
    if(canReview){
      if(course.state==='draft'&&activities.length)card.append(reviewPanel(pack,{player,sources:course.sources||[],reload:loadDay,fail,notice}));
      const actions=el('div',{class:'page-actions'});
      if(pack){const regenerate=button('重新生成互动',async()=>{regenerate.disabled=true;try{await api(`packs/${encodeURIComponent(pack.id)}/regenerate`,{method:'POST',body:{}});notice('已开始重新生成，稍后刷新查看。');}catch(error){fail(error);}finally{regenerate.disabled=false;}},'quiet');actions.append(regenerate);}
      const remove=button('删除这节课',async()=>{if(!confirm('删除这节课？素材和互动会从每日学习中移除。'))return;try{await api(`courses/${encodeURIComponent(course.id)}`,{method:'DELETE'});notice('已删除。');loadDay();}catch(error){fail(error);}},'danger-text');actions.append(remove);
      const sources=el('details',{class:'sources'},el('summary',{},`课程素材与转写 · ${(course.sources||[]).length} 份`));
      for(const source of course.sources||[])sources.append(sourcePanel(source,{canReview,reload:loadDay,fail,notice}));
      card.append(sources,actions);
    }
    body.append(card);
  }
  body.append(el('div',{class:'page-actions'},button('刷新这一天',loadDay,'secondary'),button('补传本机学习记录',flush,'quiet')));
}
window.addEventListener('online',()=>{if(state.queue)flush();});
window.addEventListener('pagehide',()=>player.stop());
boot();
