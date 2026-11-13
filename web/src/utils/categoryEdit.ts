import type { MessageCategory } from '../api/client';

type CategoryFields = Pick<MessageCategory, 'name' | 'color' | 'colorHex'>;

/** A protected default name is never sent; unchanged edits need no write. */
export function categoryEditPatch(original: CategoryFields & { isDefault?: boolean }, draft: CategoryFields): Partial<CategoryFields> | null {
  const patch: Partial<CategoryFields> = {};
  if (!original.isDefault && draft.name.trim() !== original.name) patch.name = draft.name.trim();
  if (draft.color !== original.color || (draft.colorHex ?? null) !== (original.colorHex ?? null)) {
    patch.color = draft.color;
    patch.colorHex = draft.colorHex ?? null;
  }
  return Object.keys(patch).length ? patch : null;
}
