# Production-connected Mac Electron TF 1.2.0 (86)

## Authorized scope

The owner explicitly requested a Mac TestFlight build usable on their MacBook with formal accounts/data and email login. The production Web must not include the email entry. Preserve the currently deployed Web while the owner accepts it. No Windows or native iOS change.

## Production backend evidence

- Exact deployed backend source: `e111f532669aca8f59add1f097860c446e99e76d`.
- Backend release tar SHA-256: `e5d16fd3a62e06e508dbe9be3f0d03957917b0828a1c9d55f58bb6de5e13fa7c`.
- Release directory: `/opt/synca/releases/email-20261123-e111f53`.
- Activation: 2026-11-23 18:37 Beijing time. Health returned OK; Web capability returned `email:false`; explicit desktop capability returned `email:true`.
- Web symlink remains `/opt/synca/releases/20261123T080605Z-17bd510/web`; no Web deploy in this release.
- Rehearsed migrations twice on a private consistent copy, preserving original row/column hashes across 17 existing tables and foreign-key integrity. Repeated the preservation check across the live migration under a short service stop.
- Rollback code is the previous backend with its obsolete email-based admin bootstrap removed. An email-only synthetic owner-address user stayed non-admin in the rehearsal. Rollback disables email and retains the migrated DB instead of overwriting it with an old backup.
- Server-only `activation-result.json` and `backup/rehearsal-result.json` hold evidence. `.env`, snapshots, credentials and email-signing secret have restricted permissions. No secret is committed.

## Real delivery and identity verification

At 2026-11-23 18:46 Beijing time, two actual delivered Aliyun DirectMail codes to an owner-controlled test alias were redeemed through the public production HTTPS API. The first created an ordinary non-admin account automatically; the second returned the same user with a distinct session and read back the first session's designated test record. Replaying the second code was rejected. No existing owner account was merged or modified.

Both emails landed in Outlook junk. Delivery and redemption work, but inbox placement is a known acceptance limitation. No claim is made that this validates every provider's deliverability.

Apple/email binding retains the previously tested API/UI implementation. Interactive Apple authorization with the MacBook's actual Apple ID remains a real-device acceptance check; this release does not claim that was completed by automation.

## Validation

- Full backend: 193 passed, 2 optional browser cases skipped. Targeted email/auth/migration/delivery coverage: 42 passed (included in the full run).
- Email client: 13 passed, including absence/presence of the desktop capability header and legacy preview fallback.
- MAS variant/gate/release checks: 12 passed; production evidence cannot be replaced by isolated or offline proof.
- Web and embedded desktop renderer TypeScript/production builds passed. The existing settings/layout interaction evidence remains valid for unchanged UI.
- Universal MAS package built from the official checked arm64/x64 runtime archives. Local Xcode archive succeeded; deep/strict code-sign verification passed; executable contains both x86_64 and arm64 slices; archive build number is 86 and embedded mode is `mas-production`. This local ad-hoc archive is structural validation, not the Apple-distributed installer.
- The browser fixture now explicitly opts into desktop email, matching the new rollout contract; it was not rerun as an unrestricted browser automation script.

## MacBook acceptance

1. Install 1.2.0 (86) from the existing internal Mac TestFlight group after Apple finishes processing.
2. Apple login accesses the formal account and records; the isolated preview unlock screen must not appear.
3. Email login sends a real code and enters the app directly. Check junk if it does not arrive in the inbox.
4. Settings → account and plan → login methods provides Apple→email and email→Apple binding. It does not force binding after login.
5. Command-F preserves global/pinyin search; Command-R synchronizes; settings subpages retain the restored grouped layout and Back controls.
6. Production Web continues to offer Apple login without an email entry.

Submission status and exact Cloud receipt are recorded after the dedicated manual Mac-only run is accepted. Do not equate submission with a processed downloadable build.
