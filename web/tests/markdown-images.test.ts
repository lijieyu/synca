import {api} from '../src/api/client';
const id='11111111-1111-4111-8111-111111111111';
describe('owned Markdown image lookup',()=>{
 let token:string|null,account:string|null;
 beforeEach(()=>{token='token-a';account='account-a';vi.stubGlobal('localStorage',{getItem:(key:string)=>key==='authToken'?token:key==='userId'?account:null});vi.stubGlobal('window',{location:{origin:'https://synca.test',reload:vi.fn()}});api.resetSession();});
 afterEach(()=>{api.resetSession();vi.unstubAllGlobals();});
 it('coalesces visible record lookups and resolves only IDs in the authenticated index',async()=>{
  let finish!:(value:Response)=>void;const fetch=vi.fn(()=>new Promise<Response>(resolve=>{finish=resolve;}));vi.stubGlobal('fetch',fetch);
  const first=api.markdownImageAsset('account-a',id),second=api.markdownImageAsset('account-a',id);
  finish(Response.json({images:[{id,imageUrl:'/media/owned.png'}]}));
  expect(await first).toMatchObject({id});expect(await second).toMatchObject({id});
  expect(await api.markdownImageAsset('account-a','22222222-2222-4222-8222-222222222222')).toBeNull();
  expect(fetch).toHaveBeenCalledTimes(1);
 });
 it('rejects invalid IDs and foreign account lookup without a request',async()=>{
  const fetch=vi.fn();vi.stubGlobal('fetch',fetch);
  expect(await api.markdownImageAsset('account-a','https://tracker.example')).toBeNull();
  expect(await api.markdownImageAsset('account-b',id)).toBeNull();expect(fetch).not.toHaveBeenCalled();
 });
 it.each(['switch','reset'])('does not publish or reuse an index after session %s',async(action)=>{
  let finish!:(value:Response)=>void;const fetch=vi.fn().mockImplementationOnce(()=>new Promise<Response>(resolve=>{finish=resolve;})).mockResolvedValue(Response.json({images:[]}));vi.stubGlobal('fetch',fetch);
  const pending=api.markdownImageAsset('account-a',id);if(action==='switch'){token='token-b';account='account-b';}api.resetSession();finish(Response.json({images:[{id,imageUrl:'/media/private.png'}]}));
  await expect(pending).rejects.toMatchObject({name:'AbortError'});
  expect(await api.markdownImageAsset(account!,id)).toBeNull();expect(fetch).toHaveBeenCalledTimes(2);
 });
});
