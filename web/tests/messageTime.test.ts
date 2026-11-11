import assert from 'node:assert/strict';
import { formatMessageTime } from '../src/utils/messageTime';
test('calendar dates distinguish today, yesterday, current and previous year', () => {
 const now=new Date(2026,0,1,12);
 for(const locale of ['zh-Hans','zh-Hant','en']) {
  const time=(d:Date)=>d.toLocaleTimeString(locale,{hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
  const today=new Date(2026,0,1,8,5), yesterday=new Date(2025,11,31,8,5);
  assert.equal(formatMessageTime(today.toISOString(),locale,'Yesterday %@',now),time(today));
  assert.equal(formatMessageTime(yesterday.toISOString(),locale,'Yesterday %@',now),`Yesterday ${time(yesterday)}`);
  assert.ok(formatMessageTime(new Date(2025,11,30).toISOString(),locale,'Yesterday %@',now).includes('2025'));
  assert.ok(!formatMessageTime(new Date(2026,3,1).toISOString(),locale,'Yesterday %@',now).includes('2026'));
 }
 assert.equal(formatMessageTime('invalid','en','Yesterday %@',now),'');
});

test('24 hour clock ignores locale defaults and uses zero at midnight',()=>{
 const now=new Date(2026,3,2,12);
 for(const locale of ['en-US','en-US-u-hc-h12','zh-Hans']) {
  assert.equal(formatMessageTime(new Date(2026,3,2,0,5).toISOString(),locale,'Yesterday %@',now),'00:05');
  assert.equal(formatMessageTime(new Date(2026,3,2,20,5).toISOString(),locale,'Yesterday %@',now),'20:05');
 }
});
