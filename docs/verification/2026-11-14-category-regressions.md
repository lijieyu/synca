# Category regression investigation (2026-11-14)

## Web default category save

Confirmed cause: unchanged default-category edits generated `{}` for PATCH. The backend requires at least one editable field and returns `invalid_payload` for an empty object. The manager editor also sent the protected name; both editor paths now share a change-only payload builder and close without a request when nothing changed. The default name remains noneditable. Error dialogs have localized titles and a single acknowledgment action.

Verification:
- Executed the original payload expression with an unchanged default category: reproduced an empty PATCH (failing assertion).
- `node web/tests/category-edit.test.mjs`: passed eight cases (unchanged, default name protection, null/undefined legacy shades, color/shade changes and custom rename).
- `node web/tests/locales.test.mjs`: passed.
- `npm --prefix web run build`: passed.
- Native Chrome interaction with built Web assets at `127.0.0.1:5198`, fictional account/categories and strict mock API: double-click default, save unchanged closed the editor with zero PATCH requests; change to mint saved successfully with only color/colorHex in the request.
- Screenshot: `/tmp/synca-web-default-unchanged-saved.png`.

## Mac category blank feed

Reported on the user's Mac: switching from All records to 小软件, 久念开发 or 久念营销 can leave a blank feed despite a nonzero count; refresh does not repair it, switching away/back does.

Investigation found that commit 45e1c25 removed category-specific ScrollViewReader identity on Mac and synchronously scrolled the reused lazy stack to `bottom` during category change. iOS retained per-category identity. Restored per-category identity on Mac and removed the reused-reader scroll callback. The replacement reader uses the existing appearance/layout positioning. ImageCacheManager remains unchanged.

Verification boundary: the original blank-feed symptom was NOT reproduced on this test host, either with the installed app/account or the independent synthetic-data fixture. This is a targeted mitigation of stale category geometry, not proof of the exact cause on the reporting device.

- Isolated app built from current native sources with production configuration (arm64 and x86_64): passed.
- Fixture: 82 records, including long/short/completed records, 7/4/1-record target categories; no production writes or real credentials.
- Six All → category switches: visible/accessibility record counts 1,7,4,1,7,4, with new category layout lifetime each time.
- Search from the four-record category into the one-record category: correct selection, visible target and highlight; screenshot inspected.
- Screenshot: `/tmp/synca-mac-category-fixed.png` (fictional test data, top-right counter is fixture instrumentation).
- iOS scrolling branch behavior is unchanged.

No deployment, TF build, PR/merge, or App Store submission changes performed for this batch.
