/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 时间胶囊记录加密版本
//
// 纯 additive。客户端的合并规则是「只升不降」：服务器是不可信的一方，
// 能替换加密 blob 的人也能改这个数字，所以本地已知 v3 的信永远不接受远端说的更低版本。
// 服务端这里只是把它带过去，让家人的第二台设备也能尽早知道「这封信是 v3」。

migrate((app) => {
  const collection = app.findCollectionByNameOrId('timecapsules')
  try {
    if (collection.fields.getByName('cryptoVersion')) { return }
  } catch (_) {}
  collection.fields.add(new NumberField({ name: 'cryptoVersion' }))
  app.save(collection)
}, (app) => {
  // 回滚保留字段：删掉等于把所有设备打回「版本未知」，重新暴露降级伪造面。
})
