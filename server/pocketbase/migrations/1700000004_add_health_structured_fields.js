/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 健康记录结构化字段
// 兼容旧 amountText/reaction，同时支持喝水 ml、睡眠起止、症状体温/严重程度、体检等结构化数据。

migrate((app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('healthrecords') } catch (e) { return }

  const fields = [
    ['amountValue', () => new NumberField({ name: 'amountValue' })],
    ['amountUnit', () => new TextField({ name: 'amountUnit' })],
    ['startAt', () => new DateField({ name: 'startAt' })],
    ['endAt', () => new DateField({ name: 'endAt' })],
    ['severity', () => new TextField({ name: 'severity' })],
    ['temperatureCelsius', () => new NumberField({ name: 'temperatureCelsius' })],
    ['tags', () => new JSONField({ name: 'tags' })],
  ]

  for (const [name, makeField] of fields) {
    if (collection.fields.getByName(name)) { continue }
    collection.fields.add(makeField())
  }
  app.save(collection)
}, (app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('healthrecords') } catch (e) { return }

  for (const name of ['amountValue', 'amountUnit', 'startAt', 'endAt', 'severity', 'temperatureCelsius', 'tags']) {
    const field = collection.fields.getByName(name)
    if (!field) { continue }
    collection.fields.removeById(field.id)
  }
  app.save(collection)
})
