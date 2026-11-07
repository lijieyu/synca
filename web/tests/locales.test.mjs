import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const flatten=(object,prefix='')=>Object.entries(object).flatMap(([key,value])=>typeof value==='string'?[[prefix+key,value]]:flatten(value,prefix+key+'.'));
const locales=['en','zh','zh-Hant'].map(locale=>new Map(flatten(JSON.parse(readFileSync(new URL(`../src/locales/${locale}.json`,import.meta.url),'utf8')))));
const slots=value=>[...value.matchAll(/{{(.*?)}}/g)].map(match=>match[1]).sort();
for(const locale of locales){assert.deepEqual([...locale.keys()].sort(),[...locales[0].keys()].sort());for(const[key,value]of locales[0])assert.deepEqual(slots(locale.get(key)),slots(value),key);}
assert.match(locales[2].get('ai_page.text_001'),/讀取/);
assert.equal(locales[2].get('preferences.title'),'設定');
console.log('Three-locale key and interpolation parity passed');
