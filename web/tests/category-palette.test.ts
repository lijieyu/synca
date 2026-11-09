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

import { CATEGORY_PALETTE, categoryStyle } from '../src/components/CategoryPalette';
import { readFileSync } from 'node:fs';

describe('canonical category display colors', () => {
  it.each(CATEGORY_PALETTE.slice(0, 8))('renders legacy $color exactly like its selected preset', preset => {
    expect(categoryStyle(undefined, preset.color)).toEqual(categoryStyle(preset.hex, preset.color));
    expect(categoryStyle(null, preset.color)).toEqual({ '--category-accent': preset.hex });
    expect(categoryStyle('#not-a-color', preset.color)).toEqual({ '--category-accent': preset.hex });
  });
  it.each(CATEGORY_PALETTE)('preserves explicit $name shades and accepts case-insensitive hex', preset => {
    expect(categoryStyle(preset.hex.toUpperCase(), preset.color)).toEqual({ '--category-accent': preset.hex });
  });
  it('keeps all native preset values and legacy defaults in the same order as Web', () => {
    const native = readFileSync('../ios/Synca/Shared/Models/SyncaMessage.swift', 'utf8');
    const presets = [...native.matchAll(/\.init\(name: "([^"]+)", hex: "([^"]+)", legacy: \.(\w+)\)/g)]
      .map(([, name, hex, color]) => ({ name: name.toLowerCase(), hex, color }));
    expect(presets).toEqual(CATEGORY_PALETTE.map(preset => ({ ...preset, name: preset.name.toLowerCase() })));
  });
});
