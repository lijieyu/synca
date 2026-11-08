import { z } from 'zod';

export const MAX_RECORD_TEXT_LENGTH = 10000;
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

// Count user-perceived characters, matching Swift String.count and the web composer.
// Stop at the boundary instead of allocating an array for untrusted input.
export function isRecordTextWithinLimit(value: string): boolean {
    let count = 0;
    for (const _ of segmenter.segment(value)) {
        if (++count > MAX_RECORD_TEXT_LENGTH) return false;
    }
    return true;
}

export const recordTextSchema = z.string().min(1).refine(isRecordTextWithinLimit)
    .describe(`Text, maximum ${MAX_RECORD_TEXT_LENGTH} user-perceived characters (Unicode grapheme clusters).`);

// Keep the description on the input pipeline so MCP JSON Schema includes the limit.
export const trimmedRecordTextSchema = z.string().trim().pipe(recordTextSchema)
    .describe(recordTextSchema.description!);
