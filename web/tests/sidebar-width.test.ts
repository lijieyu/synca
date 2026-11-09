import { clampSidebar, sidebarLimit } from '../src/components/SidebarFrame';
it('keeps the existing width as minimum and bounds wide layouts', () => {
  expect(clampSidebar(100, 1200)).toBe(236);
  expect(clampSidebar(900, 1200)).toBe(360);
  expect(clampSidebar(300, 1200)).toBe(300);
});
it('reserves room for the stream without destroying the saved preference', () => {
  expect(sidebarLimit(800)).toBe(320);
  expect(clampSidebar(360, 800)).toBe(320);
  expect(clampSidebar(360, 1200)).toBe(360);
  expect(clampSidebar(360, 701)).toBe(236);
});
it('falls back for invalid stored sizes', () => {
  expect(clampSidebar(NaN, 1200)).toBe(236);
  expect(clampSidebar(Infinity, 1200)).toBe(236);
});
