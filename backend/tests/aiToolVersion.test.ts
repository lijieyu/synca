import { expect, it } from 'vitest';
import { z } from 'zod';
import { versionedSchema, withVersionNotice } from '../src/aiToolVersion.js';

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
