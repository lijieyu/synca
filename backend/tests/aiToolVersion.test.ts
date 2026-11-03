import { expect, it } from 'vitest';
import { z } from 'zod';
import { versionedSchema, withVersionNotice } from '../src/aiToolVersion.js';

it.each(['0', '999'])('makes version %s notices explicitly non-blocking without changing success', (version) => {
    const original = { content: [{ type: 'text' as const, text: '{"id":"created-record"}' }] };
    const result = withVersionNotice(original, version);
    expect(result.isError).toBeUndefined();
    expect(result.content[0]).toEqual(original.content[0]);
    const notice = JSON.parse((result.content[1] as { text: string }).text);
    expect(notice).toMatchObject({ blocking: false, refreshRecommended: true });
    expect(notice.message).toContain('继续使用现有工具完成用户请求，无需等待刷新');
    expect(notice.message).toContain('已成功的操作不要重复执行');
    expect(notice.message).not.toContain('刷新后按新定义发起后续调用');
});

it('returns current-version results unchanged', () => {
    const original = { content: [{ type: 'text' as const, text: '{}' }] };
    expect(withVersionNotice(original, '1')).toBe(original);
});

it('rejects reserved business fields rather than silently replacing them', () => {
    expect(() => versionedSchema(z.object({ toolVersion: z.string() }))).toThrow('Reserved');
});
it('preserves attachment blocks, structured output and errors when appending notices', () => {
    const original = { isError: true, structuredContent: { error: 'example' }, content: [
        { type: 'image' as const, mimeType: 'image/png', data: 'AAAA' },
        { type: 'resource' as const, resource: { uri: 'synca://attachment', mimeType: 'text/plain', blob: 'AAAA' } },
    ] };
    const result = withVersionNotice(original, '999');
    expect(result.content.slice(0, 2)).toEqual(original.content);
    expect(result.isError).toBe(true);
    expect(result.structuredContent).toEqual(original.structuredContent);
    expect(result.content[2].type).toBe('text');
    expect(original.content).toHaveLength(2);
});
