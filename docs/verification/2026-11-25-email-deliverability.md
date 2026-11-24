# Synca verification-email delivery investigation — 2026-11-25

## Conclusion and scope

The inspected messages reach the receiving mail servers. Outlook classifies both current-domain samples as Junk even though its SPF, DKIM, DMARC and composite authentication all pass. The iCloud-forwarded sample was classified `notspam` by iCloud before Outlook placed it in Junk. This is not evidence that all receiving providers junk Synca email, or that the application fails to send.

The precise private Outlook reputation/content rule is not disclosed by these headers. Sender/domain/IP reputation and recipient-specific filtering remain hypotheses, not a proven root cause. No DNS, sender, region, content, IP pool, mailbox rules or provider policy was changed. No test mail, support message or purchase was made. Viewing the previously unread forwarded sample marked it read in Outlook; no mail was moved or reported.

## Current production and provider configuration

Read-only inspection of the production backend's `.env` emitted only the sender, region, feature flag and credential-presence booleans; no credential values were displayed. The configuration is `noreply@synca.haerth.cn`, `cn-hangzhou`, email enabled. Active code path at inspection: `/opt/synca/releases/20261124T172125Z-dbb2c3a/backend/dist`.

The authenticated Aliyun DirectMail console shows:

- Sender type **触发邮件**, status **正常**, display name supplied by application **Synca**.
- Domain `synca.haerth.cn` created 2026-11-23 22:46:29 (console time); DKIM, SPF, DMARC and MX all **验证通过**.
- DKIM selector `aliyun-cn-hangzhou-2048`, 2048-bit RSA public key.
- SPF: `v=spf1 include:spf1.dm.aliyun.com -all`.
- DMARC: `v=DMARC1;p=none;rua=mailto:dmarc_report@service.aliyun.com`.
- MX: priority 1, `mx01.dm.aliyun.com`.

Public DNS queries on this Mac returned those same records, including the exact current DKIM public key. One historical iCloud lookup error below does not establish a persistent DNS fault. Additional direct 1.1.1.1/8.8.8.8 checks were not executed: automatic permission review timed out twice. This is a verification gap, not evidence of resolver failure or unsafe DNS configuration.

## Actual received-message evidence

Outlook connector folder listing located two current-domain messages in **垃圾邮件**. The connector's message endpoint did not expose raw authentication headers, so the signed-in Outlook web **查看 → 查看邮件源** view supplied the header evidence. The recipient mailbox addresses and OTP bodies are intentionally omitted here.

| Sample | Provider send time (Beijing) | Received timestamp from connector (UTC) | Aliyun result | Final observed location |
| --- | --- | --- | --- | --- |
| Direct to controlled Outlook test alias | 2026-11-23 22:56:15 | 2026-11-23T14:56:25Z | `250 Send Mail OK` | Outlook Junk |
| To iCloud, forwarded by Apple to Outlook | 2026-11-25 01:11:17 | 2026-11-24T17:11:57Z | `250 Send Mail OK` | Outlook Junk |

### Direct Outlook sample

- `Message-ID`: `e34d3360-253e-4c94-8cbe-d4cca3948a15@alibaba.com`.
- `X-EnvId`: `600000373230455440`.
- Sending IP `47.90.196.151`, HELO `out196-151.us.a.dm.aliyun.com`.
- Microsoft authentication: `spf=pass` with `smtp.mailfrom=synca.haerth.cn`; `dkim=pass` for `synca.haerth.cn` and provider domain `dm-fbl.aliyuncs.com`; `dmarc=pass` for `header.from=synca.haerth.cn`; `compauth=pass reason=100`.
- `X-MS-Exchange-Organization-SCL: 5`.
- Mailbox delivery: `auth:1;dest:J;OFR:SpamFilterAuthJ;RF:JunkEmail`.

Thus the current sender's authentication was already passing when Microsoft classified the message as junk. Missing SPF/DKIM/DMARC is not the cause demonstrated by this sample.

### iCloud-forwarded sample

- `Message-ID`: `0e88f79f-5458-4ddf-b8d9-d98f0c7ef226@alibaba.com`.
- `X-EnvId`: `600000373058978965`.
- Initial Aliyun sending IP `140.205.208.10`, HELO `out208-10.dm.aliyun.com`.
- iCloud original results: SPF pass; DMARC pass; provider DKIM pass. The Synca-domain DKIM result was `temperror (dns fetch error)` on this hop.
- iCloud original filtering: `X-Proofpoint-Spam-Details: rule=notspam policy=default score=0 phishscore=0 bulkscore=0 spamscore=0`.
- Apple forwarding is explicitly identified in `X-Apple-Action`. Microsoft's receiving IP is the forwarder `123.126.78.66`, with SPF mail-from `icloud.com`; it is not the Aliyun sending IP.
- Microsoft final results: Synca DKIM pass, provider DKIM pass, DMARC pass, composite authentication pass; SCL 5 and `dest:J;OFR:SpamFilterAuthJ;RF:JunkEmail`.
- iCloud's separate `bimi=skipped reason="insufficient dmarc"` concerns logo authentication, not a DMARC failure; it is not a reason to change `p=none` as a spam-placement fix.

This proves the message traversed iCloud and was not classified as spam by the observed iCloud filter. It does not establish the original iCloud folder placement, since that mailbox view was not inspected.

## Implemented tracing improvement

Previously `sendVerificationEmail` checked RequestId and discarded both RequestId and EnvId. It now emits a single-line `[email/delivery]` receipt containing `status=provider_accepted`, an optional UUID RequestId, and an optional 10–32 digit EnvId string. Strict shape checks omit unexpected provider-controlled values. There are no mailbox addresses, OTPs, credentials, response bodies or raw exceptions in this new log.

The receipt means API acceptance only. It does not say delivered, read, inbox or junk. Error/timeout paths do not emit it; existing sanitized errors and no-retry behavior remain. Unexpected/missing optional identifier shapes cannot convert an accepted send into a failure.

No endpoint, configuration, database migration, client behavior, message content, sender or delivery-provider change is needed for this tracing addition.

## Verification and deployment boundary

- Added tests first: 2 new receipt/privacy tests failed against old code because no acceptance receipt was emitted; existing 26 delivery tests passed.
- After implementation: all **28 email delivery tests passed**, including failure/timeout paths that must not produce acceptance receipts. `npm run build` passed.
- Test configuration was mirrored to `/tmp/synca-email-vitest.config.mjs` because the existing `node_modules` symlink points outside the writable worktree and Vite otherwise cannot create its temporary bundled config. This changes only the config-file location, preserving `globals:true` and `fileParallelism:false`.
- A full-backend-suite attempt did not execute: its temporary local-listener permission review timed out. No full-suite pass is claimed. Isolated database intended for that run: `/tmp/synca-email-deliverability-20261125.sqlite`.
- These changes are local, uncommitted and undeployed at this handoff. No live receipt from this code and no new inbox-placement result has been observed.

For integration, review the four email-only files, run the backend suite with a temporary DB, then use the normal backend-only release (`scripts/deploy-release.sh backend`) after the parent task's authorized submission step. The release script builds, stages immutable output, backs up SQLite consistently, switches the backend and restarts `synca-api`; retain existing environment and sender. Verify `/health` and headerless `/auth/capabilities` without requesting a code. On the next separately authorized/user-requested login, correlate the receipt's envelope ID with the actual mail's `X-EnvId` and check the real recipient folder. Do not trigger extra email merely to populate logs. Rollback uses the previous compatible backend code; do not restore the old DB or disable email globally for this logging-only change.

## Remaining operational action

Keep the authenticated sender stable and retain user-triggered rate limits. If Outlook continues junking natural sign-ins, the useful next escalation is Aliyun's shared-pool deliverability review using the redacted sample above (timestamp, envelope ID, initial sending IP, authentication pass, SCL/Junk result). Prepare it for review, but do not send it to support without explicit authorization. Do not buy IPs, churn domains, tighten DMARC enforcement, send bulk warm-up traffic, or promise that cosmetic HTML/template changes fix an undisclosed classifier.

A recipient may deliberately mark a legitimate message **Not junk**. That improves their individual experience and supplies feedback; it is not proof of a global fix. Inbox placement must later be checked on both direct Outlook delivery and any other provider actually used, distinguishing forwarding from direct delivery.

## Official references consulted

- [Aliyun DirectMail sending FAQ](https://help.aliyun.com/zh/direct-mail/email-sending-faqs): recipient anti-spam systems decide Junk placement; inspect sending behavior/content and provider results.
- [Aliyun domain DNS requirements](https://help.aliyun.com/zh/direct-mail/user-guide/how-to-configure-sending-domain-names): domain authentication and SPF record uniqueness.
- [Aliyun DKIM configuration](https://help.aliyun.com/zh/direct-mail/what-is-dkim-and-how-to-configure-dkim-records): obtain the exact domain key and selector from the provider console.
- [Aliyun DMARC configuration](https://help.aliyun.com/zh/direct-mail/what-is-dmarc-and-how-to-configure-dmarc-records): report destinations and policy behavior; default report address belongs to Aliyun.
- [Outlook Postmaster](https://substrate.office.com/ip-domain-management-snds/postmaster): authentication requirements and sender-deliverability resources. Authentication compliance alone is not an inbox-placement guarantee.

## Coordinating release validation

The full suite executed after network permission was granted. Fourteen files passed (160 tests, 2 skipped); the AI suite initially rejected the isolated temporary filename because it lacked the required `test` substring. With a new isolated `/tmp/synca-email-release-test-20261125.sqlite`, the AI file passed all 40 tests. Thus all applicable files passed across the two runs (200 tests; the 2 existing skips remain). The initial restricted-listener failure and filename guard were test-environment issues, not product changes. Logs: `/tmp/synca-email-release-final-suite.log` and `/tmp/synca-email-release-ai-suite.log`.
