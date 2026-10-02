import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
// Execute the actual production method body with only ArkUI's storage boundary replaced.
// This proves pure input handling; it does not emulate an ArkUI device or navigation rendering.
const method = ability.match(/private handleEntryLink\(want: Want\): void \{([\s\S]*?)\n  \}/);
assert.ok(method, 'EntryAbility must retain its concrete deep-link handler');
const handle = new Function('want', 'AppStorage', method[1]);

for (const uri of ['bubutime://entry/%', 'bubutime://entry/%E0%A4%A', 'bubutime://entry/%FF',
                   'bubutime://entry/../other', 'bubutime://entry/a%2Fb', 'bubutime://entry/a?secret=x',
                   'https://example.invalid/entry/synthetic', 'bubutime://entry/']) {
  test(`cold/warm deep link safely ignores invalid URI: ${uri}`, () => {
    const writes = [];
    const store = { setOrCreate: (...args) => writes.push(args) };
    assert.doesNotThrow(() => handle({ uri }, store));
    assert.doesNotThrow(() => handle({ uri }, store));
    assert.deepEqual(writes, []);
  });
}

test('valid direct/encoded IDs survive cold/warm delivery after an invalid URI', () => {
  const writes = [];
  const store = { setOrCreate: (...args) => writes.push(args) };
  handle({ uri: 'bubutime://entry/%' }, store);
  handle({ uri: 'bubutime://entry/synthetic_ID-12' }, store);
  handle({ uri: 'bubutime://entry/%73ynthetic_ID-12' }, store);
  assert.deepEqual(writes, [['bubuOpenEntryId', 'synthetic_ID-12'], ['bubuOpenEntryId', 'synthetic_ID-12']]);
});

test('missing URI cannot change a previously requested entry', () => {
  const writes = [];
  handle({}, { setOrCreate: (...args) => writes.push(args) });
  assert.deepEqual(writes, []);
});
