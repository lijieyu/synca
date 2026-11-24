# Email login operations

## Release boundary

Web and Electron share the centered login and settings-only binding. Apple remains the first sign-in option. Formal Web discovers availability from the headerless `/auth/capabilities` response; missing configuration, a disabled service, or a failed probe hides its email entry. Desktop keeps its existing immediate entry. All clients resolve the same user ID for linked identities. No automatic account merge is performed.

The operator explicitly authorized formal Web email login on 2026-11-25. The prior desktop-only presentation restriction is removed in both backend capabilities and Web discovery. Keep `SYNCA_EMAIL_AUTH_ENABLED=true` and the existing configured sender/signing secret; no new setting, credential rotation, database change, or mail-provider change is needed. Deploy the compatible backend first (restart `synca-api`), then Web. Verify headerless and desktop capabilities both return `email:true`, then open the ordinary browser login and its email form without submitting mail. Real delivery was previously verified on 2026-11-23; entry checks alone do not reverify delivery.

To roll back this Web rollout while preserving desktop email and existing accounts, restore the previous Web assets and previous compatible backend code with the desktop-only capability response. Do not disable the global email switch unless intentionally disabling email for all clients. Do not restore an old database or roll back to the obsolete email-based admin bootstrap.

## Aliyun DirectMail configuration

Use a dedicated transactional sender subdomain under the existing owned domain, for example `mail.synca.haerth.cn`, without changing the website's current DNS records. Obtain verification/SPF/DKIM records from the actual console; do not invent DNS values. Create a triggered/transactional sender, display name `Synca`. Region must match sender (default `cn-hangzhou`).

Provision a dedicated RAM identity with `dm:SingleSendMail` only. Use resource scoping if supported by the current console policy; otherwise action-limited resource `*`. Do not use the account owner's all-purpose key. Store only on backend in mode600 environment; no keys in Git, screenshots or client build.

Required settings (see `backend/.env.example`):
- `ALIYUN_DM_ACCESS_KEY_ID`
- `ALIYUN_DM_ACCESS_KEY_SECRET`
- `ALIYUN_DM_ACCOUNT_NAME`
- `ALIYUN_DM_REGION=cn-hangzhou`
- `EMAIL_AUTH_SECRET`: cryptographically random, at least32bytes; stable across restarts, rotation invalidates pending codes.
- Optional STS: `ALIYUN_DM_SECURITY_TOKEN`, rotated with temporary keys.

No configured provider or HMAC secret produces `503 email_unavailable`; there is no fake delivery success, default verification code, or production debug endpoint.

## Service behavior

Six-digit codes expire after10minutes. Resend waits60seconds. Five wrong attempts consume the attempt budget; proofs are one-use and separate login/binding purposes. Binding also ties proof to current user/session. New accepted resend invalidates older proof; provider failure preserves the prior valid code. DirectMail timeout10seconds, no automatic retry because a timed-out request may already have been accepted.

SQLite holds throttles shared by all workers:5sends/hour/address,20/hour/clientIP,200/hour/global and1000/day/global; verification60/hour/IP. Apple binding reuses an unexpired session-specific proof and limits newly created proofs to30/hour/user, so unrelated users behind one public IP do not consume each other’s proof quota. Backend trusts forwarded clientIP only from local nginx. Logs omit code, mailbox, credentials and provider response body. Challenge metadata becomes eligible for cleanup24hours after expiry and is removed on the next incoming challenge request. Account deletion immediately removes its bound identities and pending proofs, including login proofs for its verified email. The service does not equate provider acceptance with inbox receipt.

Email identity is separate from the profile email Apple originally returned. Existing Apple users must bind email to make it a login identity. Admin privileges are explicit account data, never bootstrapped from matching an email string. Existing is_admin values are preserved.

## Migration and rollout

1. Build/test from the same revision. Back up SQLite consistently with SQLite backup API before deployment.
2. Test migration against a copy of actual schema; the migration changes only Apple identity nullability, preserves row IDs/columns/indexes/triggers and validates foreign keys. New identity/challenge/rate tables are additive. Existing session tokens remain valid.
3. Configure sender/credentials and secret before enabling users to rely on email login. Deploy compatible backend before Web/Electron. Keep old assets for open tabs. No backend/DB changes have been deployed as part of local implementation verification.
4. Verify Apple login using an existing account, receive a real code, log in/relog in, then test both binding directions with designated test accounts. Verify identity conflict refusal and second-device record sync. Do not create test accounts using a real user's Apple identity without explicit participation.
5. Check actual inbox receipt in chosen recipient providers. Provider RequestId alone is not evidence of delivery; do not publish OTPs or request user passwords.
6. After email registration is enabled, NEVER roll back to a backend containing the old migration that grants admin by matching profile email. Prepare and verify a rollback backend with that bootstrap removed first. A Web/Electron-only rollback may keep the compatible new backend. Do not overwrite a live DB with the backup; reconcile new identity/session records instead.

## Local verification

- Backend: `DB_PATH=/tmp/synca-email-test.sqlite npm exec vitest run`
- Real Web/API isolated integration (requires built Web and local Chrome; only external Apple/mail are test doubles): `DB_PATH=/tmp/synca-email-browser-test.sqlite SYNCA_BROWSER_TEST=1 npm exec vitest run tests/desktopEmail.integration.test.ts`
- Frontend browser visual/behavior check: `web/tests/email-auth.browser.mjs` with local Vite on5178. This uses mocked transport, not live provider delivery.
- Electron: build shared renderer then macOS arm64; do not build Windows under this task.

Official references: [SingleSendMail](https://help.aliyun.com/zh/direct-mail/singlesendmail), [current endpoints](https://help.aliyun.com/zh/direct-mail/api-endpoints), [RPC signature](https://www.alibabacloud.com/help/en/direct-mail/signature).
