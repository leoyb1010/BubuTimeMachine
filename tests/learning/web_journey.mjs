/** Real-browser contract fixture, not production content. Run: node tests/learning/web_journey.mjs */
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require('playwright'); // Supply NODE_PATH when Playwright is installed in a shared runtime.
const root=resolve('server/ai/learning/web'), output=resolve('work/learning-web-proof');await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname.split('/').pop();const file=(!name || name==='learning')?'index.html':name;if(!/^[a-z_.]+$/.test(file))throw Error();const body=await readFile(resolve(root,file));res.setHeader('Content-Type',({'html':'text/html','js':'text/javascript','css':'text/css'})[extname(file).slice(1)]||'text/plain');res.end(body);}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true});
const context=await browser.newContext({viewport:{width:1280,height:1000},reducedMotion:'reduce'});const page=await context.newPage();
const mobileLayout=[];
async function assertMobileChoicesVisible(label){
 await page.waitForFunction(()=>[...document.querySelectorAll('.lesson img')].every(image=>image.complete&&image.naturalWidth>0));
 assert.equal(await page.locator('.lesson .question-context img').count(),1);
 const metrics=await page.evaluate(()=>({choices:[...document.querySelectorAll('.choice')].map(node=>{const box=node.getBoundingClientRect();return {top:box.top,bottom:box.bottom,height:box.height,font:parseFloat(getComputedStyle(node).fontSize)};}),audio:[...document.querySelectorAll('.audio-controls button')].map(node=>node.getBoundingClientRect().height),height:innerHeight,width:innerWidth,scroll:scrollY}));
 assert.equal(metrics.scroll,0);assert.equal(metrics.choices.length,2);assert.ok(metrics.choices.every(choice=>choice.top>=0&&choice.bottom<=metrics.height&&choice.height>=44&&choice.font>=18),JSON.stringify(metrics));assert.ok(metrics.audio.every(height=>height>=44));mobileLayout.push({label,...metrics});
}
const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.addInitScript(()=>{window.playedAudio=[];window.Audio=class{constructor(url){this.url=url;this.currentTime=0;}addEventListener(){}pause(){}async play(){window.playedAudio.push(this.url);}};});
const clip=(role,name)=>({role,audio_url:`/learning/media/${name}.wav`,text:role==='answer'?'Corn.':'Can you find corn?',start:1,end:2,source_id:'source1',segment_id:name});
const activities=['listen_choice','color_choice','sort','speak','music'].map((kind,i)=>({id:`a${i}`,kind,title:['听一听，找到玉米','听老师说，选一组颜色','放进野餐篮','轮到你来说','一起唱秋天的歌'][i],concept:'corn',instruction:'听老师的原声，再试试看。',review_digest:`digest-${i}`,prompt:clip(kind==='music'?'context':'question',`prompt-${i}`),answer:kind==='music'?null:clip('answer',`answer-${i}`),...(['listen_choice','color_choice','sort'].includes(kind)?{choices:[{id:'corn',label:'corn',...(kind==='color_choice'?{color:'#f2c84f'}:{image_url:'/learning/media/corn.svg'})},{id:'pumpkin',label:'pumpkin',...(kind==='color_choice'?{color:'#e98a42'}:{image_url:'/learning/media/pumpkin.svg'})}],correct_choice:'corn'}:{})}));
activities[0].prompt.image_url='/learning/media/context.svg';
activities[1].prompt.image_url='/learning/media/context.svg';
activities[3].prompt.image_url='/learning/media/context.svg';
activities[1].choices=[{id:'corn',label:'Yellow and green',colors:['#f2c84f','#729668']},{id:'pumpkin',label:'Orange and green',colors:['#e98a42','#729668']}];
let status='draft',loggedIn=false,denyPacks=false,conflict=false,offlineAttempts=false,attempts=[],publication=null,sourcePatch=null;
const pack=()=>({id:'pack1',child_id:'bubu',school_date:'2026-10-21',revision:3,status,title:'秋天的野餐小发现',payload:{summary:'听老师说，动手找一找。把今天的玉米、颜色和儿歌串成一次亲子小冒险。',activities,warnings:[]},confirmations:activities.map(a=>({activity_id:a.id,digest:a.review_digest}))});
const source={id:'source1',revision:2,name:'老师的教学原片',kind:'video',state:'ready',school_date:'2026-10-21',date_confirmed:true,original_url:'/learning/media/source.mp4',analysis:{segments:[{id:'seg1',start:1,end:2,text:'Can you find corn?'}]}};
await page.route('**/learning/media/**',route=>route.fulfill({status:200,contentType:'image/svg+xml',body:route.request().url().includes('pumpkin') ? '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="160"><path d="M100 35 Q100 5 120 12" stroke="#729668" stroke-width="12" fill="none"/><ellipse cx="100" cy="95" rx="77" ry="58" fill="#e58d45"/><ellipse cx="100" cy="95" rx="33" ry="58" fill="#f2a359"/></svg>' : '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="160"><rect x="65" y="10" width="65" height="135" rx="32" fill="#e4ba48"/><path d="M70 140 Q10 50 65 70 Q110 100 115 140" fill="#729668"/></svg>'}));
await page.route('**/learning/api/**',async route=>{
 const request=route.request(),url=new URL(request.url()),path=url.pathname.slice('/learning/api/'.length),method=request.method();
 assert.equal(request.headers()['x-bubu-learning'],'1');
 const json=(body,statusCode=200)=>route.fulfill({status:statusCode,contentType:'application/json',body:JSON.stringify(body)});
 if(path==='session'){loggedIn=method==='POST';return json({ok:true});}
 if(!loggedIn)return json({error:'auth'},401);
 if(path==='context')return json({user:{id:'mom',can_review:true},children:[{id:'bubu',name:'布布'}],default_child:'bubu',school_inbox_display:'布布幼儿园',source_status:{last_sync:'2026-10-21T09:30:00Z'}});
 if(path==='days')return json({days:[{date:'2026-10-21',source_count:1,published_count:status==='published'?1:0}]});
 if(path==='packs')return denyPacks?json({},403):json({items:url.searchParams.get('date')==='2026-10-21'?[pack()]:[]});
 if(path==='sources')return json({items:[source]});
 if(path==='packs/pack1/publish'){publication=request.postDataJSON();if(conflict)return json({},409);status='published';return json(pack());}
 if(path==='packs/pack1/exclude'){status='draft';return json(pack());}
 if(path==='packs/pack1/regenerate' || path==='sync')return json({queued:true});
 if(path==='sources/source1/segments'){sourcePatch=request.postDataJSON();return json(source);}
 if(path==='reviews')return json({window_start:'2026-10-15',window_end:'2026-10-21',items:status==='published'?activities.map(activity=>({pack_id:'pack1',activity_id:activity.id,concept:activity.concept,reason:'已确认，隔几天再遇见',activity})):[]});
 if(path==='attempts'){if(offlineAttempts)return route.abort('internetdisconnected');attempts.push(request.postDataJSON());return json({id:attempts.at(-1).id});}
 return json({},404);
});
try {
 await page.goto(`${base}/learning?date=2026-10-21`);await page.getByLabel('账号',{exact:true}).fill('mom');await page.getByLabel('密码',{exact:true}).fill('secret');await page.getByRole('button',{name:'打开家庭学习小屋'}).click();
 await page.getByRole('heading',{name:'秋天的野餐小发现'}).waitFor();assert.equal(await page.getByRole('button',{name:'开始今天的小发现 →'}).count(),0);
 await page.screenshot({path:`${output}/desktop-draft.png`,fullPage:true});
 await page.locator('.review-panel > summary').click();await page.getByRole('button',{name:'听题目原声'}).first().focus();await page.keyboard.press('Enter');
 assert.deepEqual(await page.evaluate(()=>window.playedAudio.map(x=>new URL(x).pathname)),['/learning/media/prompt-0.wav']);
 assert.equal(await page.locator('.review-panel .question-context img').count(),3);
 await page.getByRole('button',{name:'单独听答案'}).first().click();assert.equal((await page.evaluate(()=>window.playedAudio)).length,2);
 for(const checkbox of await page.locator('.review-panel input[type=checkbox]').all())await checkbox.check();
 conflict=true;await page.getByRole('button',{name:'确认并开放给孩子'}).click();await page.getByText('内容已更新，旧确认已失效。请重新加载并核对当前版本。').waitFor();
 await page.locator('.review-panel > summary').click();assert.equal(await page.locator('.review-panel input:checked').count(),0);conflict=false;
 for(const checkbox of await page.locator('.review-panel input[type=checkbox]').all())await checkbox.check();await page.getByRole('button',{name:'确认并开放给孩子'}).click();await page.getByRole('button',{name:'开始今天的小发现 →'}).waitFor();assert.equal(publication.revision,3);assert.equal(publication.confirmations.length,5);assert.ok(publication.confirmations.every(x=>x.verified&&x.digest));
 await page.getByRole('button',{name:'开始今天的小发现 →'}).click();await page.getByRole('button',{name:'▶ 听老师的题目'}).click();assert.equal((await page.evaluate(()=>window.playedAudio)).at(-1),`${base}/learning/media/prompt-0.wav`);
 await page.screenshot({path:`${output}/desktop-lesson.png`,fullPage:true});
 offlineAttempts=true;await page.getByRole('button',{name:'corn',exact:true}).click();await page.getByText(/已保存在这台设备/).waitFor();assert.equal(attempts.length,0);
 offlineAttempts=false;await page.evaluate(()=>window.dispatchEvent(new Event('online')));await page.getByText('本机的学习记录已同步。').waitFor();assert.equal(attempts.length,1);
 await page.getByRole('button',{name:'下一个小发现 →'}).click();assert.equal(await page.locator('.question-context img').count(),1);assert.equal(await page.locator('.swatch-group .swatch').count(),4);await page.getByRole('button',{name:'Yellow and green',exact:true}).click();await page.getByText('找到了！还想再听一次也可以。').waitFor();assert.equal(await page.locator('.selected-color-band span').count(),2);await page.screenshot({path:`${output}/color-combination.png`,fullPage:true});await page.setViewportSize({width:390,height:844});await page.evaluate(()=>window.scrollTo(0,0));await assertMobileChoicesVisible('color-combination');await page.screenshot({path:`${output}/mobile-color-combination.png`,fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.setViewportSize({width:1280,height:1000});
 await page.getByRole('button',{name:'下一个小发现 →'}).click();await page.getByRole('button',{name:'corn',exact:true}).click();await page.getByRole('button',{name:'把「corn」放进篮子 ↓'}).click();await page.getByText('找到了！还想再听一次也可以。').waitFor();
 await page.getByRole('button',{name:'下一个小发现 →'}).click();assert.equal(await page.locator('.question-context img').count(),1);assert.equal(await page.locator('.speech-orbit').count(),0);await page.getByRole('button',{name:'我说好了'}).click();await page.getByText('这次小尝试已经记下啦。').waitFor();
 await page.getByRole('button',{name:'下一个小发现 →'}).click();await page.getByRole('button',{name:'♪ 跟着节奏拍一拍'}).click();await page.getByRole('button',{name:'我们听完啦'}).click();await page.getByText('这次小尝试已经记下啦。').waitFor();await page.getByRole('button',{name:'完成今天的活动'}).click();await page.getByRole('button',{name:'回到课程日历'}).click();assert.equal(attempts.length,5);assert.equal(new Set(attempts.map(x=>x.id)).size,5);
 await page.getByRole('button',{name:'近 7 天重温'}).click();await page.getByRole('button',{name:'开始一起重温'}).waitFor();await page.getByRole('button',{name:'近 30 天重温'}).click();await page.getByRole('button',{name:'开始一起重温'}).waitFor();
 await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'按日期学'}).click();await page.getByRole('button',{name:'开始今天的小发现 →'}).waitFor();await page.screenshot({path:`${output}/mobile-day.png`,fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.getByRole('button',{name:'开始今天的小发现 →'}).click();await assertMobileChoicesVisible('listen-choice');await page.screenshot({path:`${output}/mobile-lesson.png`,fullPage:true});await page.setViewportSize({width:1024,height:768});await page.screenshot({path:`${output}/tablet-lesson.png`,fullPage:true});await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.getByRole('button',{name:'← 回到课程'}).click();
 await page.locator('.sources > summary').click();await page.locator('.source-card > summary').click();await page.locator('.transcript-editor > summary').click();await page.getByLabel('seg1 转写文字').fill('What is it?');await page.getByLabel('我已对照原片核实上述转写和日期').check();await page.getByRole('button',{name:'保存校正，重新核对课程'}).click();await page.getByText('校正已保存，旧确认已失效。请重新生成并核对课程。').waitFor();assert.equal(sourcePatch.revision,2);assert.equal(sourcePatch.segments[0].text,'What is it?');
 await page.getByLabel('后一天').click();await page.getByRole('heading',{name:'这一天还没有互动课程'}).waitFor();await page.screenshot({path:`${output}/mobile-empty.png`,fullPage:true});
 denyPacks=true;await page.getByLabel('前一天').click();await page.getByRole('heading',{name:'暂时没有访问权限'}).waitFor();await page.screenshot({path:`${output}/mobile-forbidden.png`,fullPage:true});assert.equal(await page.getByRole('button',{name:'重新加载',exact:true}).count(),0);
 assert.deepEqual(errors,[]);console.log(JSON.stringify({result:'PASS',viewports:['1280x1000','390x844','1024x768'],journeys:['login','draft-gate','question-only-audio','explicit-answer','409-reset','publish-digests','five-activities','offline-queue-retry','week-month-review','source-correction','empty','403-no-retry'],attempts:attempts.length,mobileLayout,screenshots:output},null,2));
} finally {await browser.close();server.close();}
