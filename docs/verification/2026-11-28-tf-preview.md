# Synca 1.2.1 TF and Preview acceptance release

User authorized normal TF packaging and Preview Web deployment, then explicitly
selected production accounts/data for cross-device acceptance. Public Web is not
part of this release. No Store submission or public Windows replacement is included.

## Deployed application revision

- Product code: `1481bebcf20f0eb4739d4c18e6e5c10cab4acb87`.
- Production backend: `/opt/synca/releases/20261128T145012Z-1481beb`.
- Preview frontend: `/opt/synca-preview/web-releases/20261128T145114Z-1481beb-web`.
- Preview URL: https://synca-preview.haerth.cn/ (existing access gate retained).
- TF follows the normal dev → main PR #134 automatic packaging workflow. Build
  processing/installation availability is not checked or asserted by this report.

## Evidence

- Prior Markdown corpus, client, Windows and native evidence remains applicable:
  `docs/markdown-parity-acceptance-2026-11-28.md`.
- Release metadata, native Markdown bundle drift and deployment routing checks passed.
- Current backend TypeScript and Preview frontend production builds passed.
- A consistent production SQLite backup was migrated twice on-server. Hashes of
  original columns/rows in all 21 pre-existing tables remained equal; integrity
  and foreign-key checks passed. The rehearsal does not access or export record
  content outside the server.
- Backend deployment created another consistent backup before additive migration,
  restarted the API, and passed its health/ingress checks.
- Preview HTTPS checks: missing access gate rejects API calls; a valid gate still
  requires product account authentication; new scratchpad/sync routes reach the
  product API; the internal gate endpoint cannot be requested externally.
- Authenticated Preview HTML, referenced JS/CSS assets and logo returned 200.
  Public Web index hash remained unchanged by Preview deployment.

## Maintenance and rollback

Run `bash scripts/deploy-preview-production.sh` to explicitly deploy Preview against
production accounts. It retains the existing isolated service as the access gate
and static host, while Nginx forwards business APIs to the one production API on
port 3002. It does not start a second API against the production SQLite database.
The isolated test database remains intact and is no longer used by Preview clients.

Routine frontend updates may continue using `scripts/deploy-preview-web.sh`;
existing Nginx production routing stays in place. Do not run the legacy
`deploy-preview.sh` as a replacement for this active email-preview process.

Routing snapshots live under `/opt/synca-preview/routing-releases/`; the active
snapshot is named by `/opt/synca-preview/current-production-routing`. Restore its
`previous.conf` to `/etc/nginx/sites-enabled/synca-preview`, validate with `nginx -t`,
then reload Nginx to roll back routing. Preview frontend snapshots retain
`previous-web` alongside each deployment. Backend rollback uses its release backup;
never overwrite the live database as part of a code rollback.

## User acceptance

Use the same existing account/login method in Preview and TF. A previous isolated
Preview login is not a production session and requires signing in again. Edits,
collections and deletions in Preview affect real records.

1. Records: use the shared Markdown sample, verify headings, nested lists, quotes,
   tables, links, code, task lists and images on iPhone, Mac and Preview.
2. Scratchpad: edit across devices, verify automatic saving/sync and task toggles;
   simultaneous edits must preserve recoverable content.
3. Collections: add a temporary record to Collections, check category filtering and
   global search; it must not count as an unfinished task.

Real-account sign-in and authenticated cross-device editing remain user acceptance
steps; no user login was fabricated or session token extracted during deployment.
