# Web launch polish implementation plan

Goal: ship a restrained Web polish release with correct current pricing and safe storage quotas.
Approved by user 2026-11-09: prioritize Web; preserve black-on-light / white-on-dark All identity but reduce weight; real moving-row reorder in sidebar and manager; Free100MiB/3d, paid1GiB/30d; update production. App Store mainland lifetime price verified CNY98. Keep native UI unchanged this batch.

## Task A — Web interactions
- Replace drop-only HTML drag with pointer/keyboard sortable behavior: picked whole row follows pointer, siblings animate into insertion slot; move not copy; cancel/outside restores, drop persists once, error rollback. Default stays fixed. Preserve click selection/composer focus, double-click edit, inline rename and concurrent polling safety.
- New/edit category modal displays16 preset swatches directly, manager compact swatch popover retained. Palette must not be clipped.
- All identity stays black/light and white/dark with lighter visual weight than prior solid slab, distinguish Default.
- Align refresh/brush visual weights and dim completed category dot, without reworking accepted layout.
- Test ordering boundaries, cancellation, save failure, polling; actual pointer drag in both surfaces, light/dark screenshots, narrow viewport.

## Task B — Storage and price
- backend storagePolicy100MiB free,1GiB paid;3/30days. Keep file capabilities and single attachment limits.
- No quota-based deletion or retroactive expiration. Existing attachment expiration preserved;30d applies new paid uploads. Overquota retains download/delete and blocks only upload.
- Web all three locale benefits reflect100MB/1GB/30d, price98 and concise mainland-price qualifier. Backend legal copy consistent. Native fallback/copy only if needed to avoid false2GB promise; do not redesign native.
- Boundary and existing-file behavior tests. Build + backend/web suites.

## Task C — Release safety (root)
- Preserve prior hashed Web assets across atomic deploy so open old tabs can lazy-load chunks.
- Check additive API/category compatibility, no production test-data copy, backup and rollback.
- Integrate review, preview and screenshot first; user authorizes production Web/backend in current request. Deploy validated artifacts, verify public entry/assets/health and authoritative usage. No ASC edits/TF rebuild/new native release.

## Review focus
- Drag vs click/double-click and touch scroll, pointer cancellation.
- Polling or save completion must not clobber draft/order.
- Overquota files remain readable; expired files never resurrected.
- New benefits match backend; old client API remains supported.
- Open older tabs can retrieve old hashed assets after release.
