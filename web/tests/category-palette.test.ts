import { api } from '../src/api/client';
afterEach(() => vi.unstubAllGlobals());
it('sends the additive shade and keeps an older server response authoritative', async () => {
  vi.stubGlobal('localStorage', {getItem: () => 'session'});
  const oldCategory = {id:'category',name:'Work',color:'sky'};
  const fetch = vi.fn(async () => new Response(JSON.stringify(oldCategory)));
  vi.stubGlobal('fetch',fetch);
  const result = await api.updateMessageCategory('category',{color:'sky',colorHex:'#4169a8'});
  expect(result).toEqual(oldCategory);
  expect(result.colorHex).toBeUndefined();
  expect(fetch).toHaveBeenCalledWith('/message-categories/category',expect.objectContaining({method:'PATCH',body:JSON.stringify({color:'sky',colorHex:'#4169a8'}),headers:expect.objectContaining({Authorization:'Bearer session'})}));
});
it('keeps legacy category creation valid without a shade', async () => {
  vi.stubGlobal('localStorage',{getItem:()=> 'session'});
  const fetch=vi.fn(async()=>new Response(JSON.stringify({id:'category',name:'Work',color:'sky'})));
  vi.stubGlobal('fetch',fetch);
  await api.createMessageCategory('Work','sky');
  expect(fetch).toHaveBeenCalledWith('/message-categories',expect.objectContaining({body:JSON.stringify({name:'Work',color:'sky'})}));
});
