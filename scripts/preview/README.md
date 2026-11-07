# Synca isolated Web preview

Target: `https://synca-preview.haerth.cn`. Production `synca.haerth.cn` is never switched by these scripts.

- Code: `/opt/synca-preview/releases/<id>`; PM2 process: `synca-preview`; listener: `127.0.0.1:3004`.
- Database: `/opt/synca-preview/state/data/preview.sqlite`; attachments and feedback are under the same independent state directory.
- No production users, sessions, data, Apple credentials, push keys or purchase receipts are copied.
- `server.mjs` wraps the unchanged product backend. Preview identity/session endpoints exist only in this wrapper, never in production app builds.
- Nginx protects `/__preview/unlock` with Basic auth and grants a Secure/HttpOnly/SameSite=Lax cookie. The app keeps its original Bearer authorization; never apply Basic auth globally, as the two share one HTTP header.
- Default proxy strips `X-Preview-Authenticated`; only the authenticated unlock location may set it. Do not publish port 3004.
- Free and Unlimited fixture profiles are separate test accounts. Editing, categories, attachments, appearance, languages and feedback use real isolated backend persistence. Apple sign-in, purchases, push and admin actions are disabled. External AI clients cannot traverse the private preview gate and require separate integration acceptance.
- Preview banner/bootstrap is injected into the staging artifact. The production Web build/source gets no test login or preview token.

## Update

Run `bash scripts/deploy-preview.sh`. It builds current source (including uncommitted UI work), installs separate dependencies, copies public Apple root certificates and restarts only `synca-preview`. The production deployment script is not used.

First provisioning additionally requires DNS A record `synca-preview` → `123.56.247.129`, certificate issuance through `/var/www/synca-preview-acme`, and activation of `nginx-https.conf` as the dedicated preview vhost. Generate the preview Basic access password outside source control; store its hash at `/opt/synca-preview/access.htpasswd` and readable admin copy at `/opt/synca-preview/access-password` (0600). Never include secrets in release artifacts or URLs.

## Verification

`check.mjs` exercises the isolated API on the server. `proxy-check.py` verifies real nginx auth + Bearer + upload/download through a temporary loopback-only copy of the preview vhost on 3044; it is not a public test endpoint. Tests write fixture records only. Remove the loopback vhost after verification.

Before/after activation, compare `/opt/synca/web/index.html`, the live release symlink and production nginx configuration, and check the production `/health` response. Do not migrate or restart the production backend.

## Provisioned 2026-11-07

- Aliyun A record enabled, TTL 10 minutes; independent certificate issued (expires 2027-02-05, automatic renewal configured).
- Active release: `/opt/synca-preview/releases/20261107T093444Z-9f7a8d1-preview`.
- HTTPS gate, secure cookie, Bearer profile/list, isolated text create/edit and attachment upload/download passed through nginx; forged gate header rejected.
- Public Chrome entry, free account, exposed quota, category add, unified menu and Settings dialog verified. Browser tab retained for acceptance.
- Production Web remains `/opt/synca/releases/20261105T163234Z-d5e5823/web`. Production index and nginx config hashes match baseline; API health OK; process not restarted.
- Temporary loopback-only nginx test vhost removed. Access password is kept only in the server admin file, not source control.
