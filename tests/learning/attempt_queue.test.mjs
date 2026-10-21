import test from 'node:test';
import assert from 'node:assert/strict';
import {AttemptQueue, APIError} from '../../server/ai/learning/web/api.js';
const storage = () => {const map = new Map(); return {getItem:k=>map.get(k),setItem:(k,v)=>map.set(k,v)};};
test('offline attempt remains pending and retries exact id once online', async () => {
 const db=storage(), sent=[]; let offline=true;
 const queue=new AttemptQueue({userId:'mom',childId:'bubu',storage:db,send:async x=>{if(offline)throw new TypeError('offline');sent.push(x);}});
 const row={id:'uuid1',child_id:'bubu',choice:'corn'};
 assert.equal((await queue.add(row)).pending,1); offline=false; assert.equal((await queue.flush()).pending,0); assert.deepEqual(sent,[row]);
});
test('user and child queues are isolated and auth failures are not treated as synced', async () => {
 const db=storage(); const make=(userId,childId)=>new AttemptQueue({userId,childId,storage:db,send:async()=>{throw new APIError(403,'forbidden');}});
 const mom=make('mom','bubu'); assert.equal((await mom.add({id:'one',child_id:'bubu'})).error.status,403);
 assert.equal(make('grandma','bubu').pending.length,0); assert.equal(make('mom','sibling').pending.length,0); assert.equal(make('mom','bubu').pending.length,1);
 await assert.rejects(mom.add({id:'bad',child_id:'sibling'}));
});

test('403 blocks automatic repeated sends until a fresh queue is opened', async () => {
 let calls=0;const queue=new AttemptQueue({userId:'mom',childId:'bubu',storage:storage(),send:async()=>{calls++;throw new APIError(403,'forbidden');}});
 await queue.add({id:'one',child_id:'bubu'});await queue.flush();await queue.flush();assert.equal(calls,1);assert.equal(queue.pending.length,1);
});
