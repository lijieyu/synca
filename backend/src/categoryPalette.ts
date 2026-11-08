import { z } from 'zod';
import type { SyncaMessageCategoryColor } from './types.js';

// Wire tokens must remain compatible with the original native enum.
export const categoryColorTokens = ['sky', 'mint', 'amber', 'coral', 'violet', 'slate', 'rose', 'ocean'] as const;
export const categoryPalette = [
    { name: 'Sky', hex: '#3b82f6', color: 'sky' },
    { name: 'Mint', hex: '#22c55e', color: 'mint' },
    { name: 'Amber', hex: '#f59e0b', color: 'amber' },
    { name: 'Coral', hex: '#ef4444', color: 'coral' },
    { name: 'Violet', hex: '#a855f7', color: 'violet' },
    { name: 'Slate', hex: '#64748b', color: 'slate' },
    { name: 'Rose', hex: '#ec4899', color: 'rose' },
    { name: 'Ocean', hex: '#06b6d4', color: 'ocean' },
    { name: 'Graphite', hex: '#676d78', color: 'slate' },
    { name: 'Denim', hex: '#4169a8', color: 'sky' },
    { name: 'Teal', hex: '#4a9a9d', color: 'ocean' },
    { name: 'Olive', hex: '#8da35e', color: 'mint' },
    { name: 'Honey', hex: '#d9b24b', color: 'amber' },
    { name: 'Peach', hex: '#df8e73', color: 'coral' },
    { name: 'Berry', hex: '#af597b', color: 'rose' },
    { name: 'Lavender', hex: '#8276c2', color: 'violet' },
] as const satisfies ReadonlyArray<{ name: string; hex: string; color: SyncaMessageCategoryColor }>;
export const categoryColorSchema = z.string().trim().pipe(z.enum(categoryColorTokens));
export const categoryColorHexSchema = z.string().trim().toLowerCase()
    .refine(hex => categoryPalette.some(preset => preset.hex === hex), 'Unsupported category color').nullable();

export function categoryColorPatch(input: { color?: SyncaMessageCategoryColor; colorHex?: string | null }, existing: { color: string; color_hex?: string | null }) {
    if (input.colorHex != null) {
        const hex = categoryColorHexSchema.parse(input.colorHex)!;
        return { color: categoryPalette.find(preset => preset.hex === hex)!.color, color_hex: hex };
    }
    return { color: input.color ?? existing.color,
        color_hex: input.colorHex === null || input.color !== undefined ? null : existing.color_hex ?? null };
}
