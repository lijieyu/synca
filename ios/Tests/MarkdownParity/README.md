# Native Markdown parity fixture

The generator copies current native sources into a new temporary directory and consumes the exact `showcase` case from `tests/fixtures/markdown-parity.json`. The temporary app uses the real record block view, scratchpad preview, source editor and task handlers. Record writes are deliberately replaced by a delayed in-memory fixture response; failure/conflict launch flags verify rollback, not production synchronization. Keychain, account, cache directory and bundle identifier are isolated; API endpoints point only to loopback, with fixture sync and asset metadata loads disabled. No live account is needed.

```sh
bash ios/Tests/run-message-markdown.sh
bash ios/Tests/run-scratchpad.sh
python3 ios/Tests/MarkdownParity/make-fixture.py /tmp/synca-markdown-qa-new
xcodebuild -project /tmp/synca-markdown-qa-new/Synca.xcodeproj -scheme Synca \
  -destination 'platform=iOS Simulator,id=EXISTING_DEVICE_UUID' \
  -derivedDataPath /tmp/synca-markdown-qa-build CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -only-testing:PolishUITests/MarkdownParityTests \
  -resultBundlePath /tmp/synca-markdown-qa.xcresult test
```

Reuse an existing iPhone or iPad and run only one simulator at a time. The owner of the simulator must shut it down after captures. The same fixture builds with `-scheme SyncaMac` for native macOS inspection. `Record` / `Scratchpad` use the same source; `Dark` changes appearance; `Source` opens the actual record editor. The initial record is expanded, with its real collapse control available below the content.

UI tests capture both surfaces in light/dark and maximum accessibility text, scroll to code/table content, exercise task success/failure/conflict, and inspect original Markdown in the editor. Failure cases use `-qa-task-failure` and `-qa-task-conflict`. Source-state instrumentation exists only in the temporary fixture. Parser tests cover all shared fixtures, literal images in code, safe links, source-preserving UTF-16 task edits, plain whitespace, renderer attributes, nested indentation and parser-resource failure fallback.

Manual checks: short tasks remain directly interactive; collapsed long records expose no invisible task controls; expand/collapse preserves feed behavior; code/tables scroll horizontally within available width; multiline text and links are selectable; editor/copy retain source; large text does not clip controls. Documents over 32k UTF-16 units parse on a background actor with a loading indicator. Lists with more than 128 complex/task items use explicit Previous/Next groups; search opens the matching group. Long noninteractive text/list runs use coalesced TextKit storage. `-qa-fixture large-tasks` exercises 250k input, `-qa-fixture images` checks owned/foreign/literal images, `-qa-fixture image-nesting-table` checks nested and table images, `-qa-uppercase-images` covers case-insensitive owned-image schemes, and `-qa-encoded-images` covers entity-encoded owned-image destinations. Image UI assertions require reachable Image accessibility elements, and source checks target the actual `message-text-editor` field. The owned bitmap is bundled and returned by fixture-only image transport; no image HTTP request is made.
