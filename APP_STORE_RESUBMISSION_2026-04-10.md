# Synca App Store Resubmission Notes

## Rejection Summary

Guideline 3.1.2(c) - Business - Payments - Subscriptions

Apple requested that the app's subscription flow include:

- A functional link to the Terms of Use (EULA)
- A functional link to the Privacy Policy
- Clear subscription information shown within the app

Apple also requested matching metadata updates in App Store Connect.

## Code Changes Completed

The in-app purchase flow has been updated on both iPhone and Mac in the access / upgrade screen:

- Added a dedicated "Subscription Information" section
- Explicitly shows the monthly and yearly subscription options with billing period and price
- Added functional links to:
  - Privacy Policy
  - Terms of Use
- Added a subscription management / auto-renewal note
- Kept the same subscription information block visible even after a subscription is active

Updated files:

- `ios/Synca/Shared/Views/AccessCenterView.swift`
- `ios/Synca/Shared/Core/AppLinks.swift`
- `ios/Synca/Resources/en.lproj/Localizable.strings`
- `ios/Synca/Resources/zh-Hans.lproj/Localizable.strings`

Verification completed:

- iPhone build: `Synca` Production build succeeded
- Mac build: `SyncaMac` Production build succeeded

## URLs

Use these production URLs in both the app and App Store Connect:

- Privacy Policy (EN): `https://synca.haerth.cn/en/privacy-policy`
- Terms of Use (Apple Standard EULA): `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- Support (EN): `https://synca.haerth.cn/en/support`
- Privacy Policy (ZH): `https://synca.haerth.cn/zh-hans/privacy-policy`
- Terms of Use (Apple Standard EULA): `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- Support (ZH): `https://synca.haerth.cn/zh-hans/support`

## App Store Connect Updates

### Required fields

Set or confirm the following:

- Privacy Policy URL:
  - `https://synca.haerth.cn/en/privacy-policy`

### Terms of Use / EULA metadata

Synca should use Apple's standard EULA for this resubmission:

- In App Store Connect, keep the standard Apple EULA
- Do not add a custom EULA
- Add the standard EULA link in the App Description
- In-app, the Terms of Use button should open the standard Apple EULA URL

### App Description addition

Append these lines to the end of the English App Description:

`Privacy Policy: https://synca.haerth.cn/en/privacy-policy`

`Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

Append these two lines to the end of the Chinese App Description if you maintain localized metadata:

`隐私政策：https://synca.haerth.cn/zh-hans/privacy-policy`

`使用条款：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

### Review Notes

Paste this in App Review Notes:

`The subscription screen has been updated on both iPhone and Mac to include:`
`1. functional Privacy Policy and Terms of Use links,`
`2. clear monthly and yearly subscription information,`
`3. subscription management / auto-renewal notice.`
`4. the same legal links and subscription information remain visible in the access center after purchase.`
`Please refer to the attached screen recording showing the access / purchase screen and the legal links in the app.`

## Reply to App Review

Recommended English reply:

`Hello App Review Team,`

`Thank you for the feedback. We have updated the app and App Store Connect metadata to address Guideline 3.1.2(c).`

`In the latest build, the subscription screen on both iPhone and Mac now includes:`
`- functional links to the Privacy Policy and Terms of Use,`
`- clear monthly and yearly subscription information, including billing period and price,`
`- subscription management / auto-renewal notice.`
`The same information remains visible in the access center after purchase as well.`

`We also updated the App Store metadata to include the Privacy Policy URL and the standard Apple Terms of Use (EULA) link in the App Description.`

`A screen recording has been attached showing the updated subscription screen and the legal links.`

`Thank you for your review.`

## Screen Recording Checklist

Record both iPhone and Mac if possible. A short recording is enough.

Suggested sequence:

1. Launch the app
2. Sign in if needed
3. Open the access / unlimited / purchase screen
4. Pause on the monthly and yearly subscription information
5. Show the Privacy Policy link
6. Tap the Privacy Policy link so the page opens
7. Return to the app
8. Show the Terms of Use link
9. Tap the Terms of Use link so the page opens
10. If possible, show the current subscribed state as well, where the same subscription information block remains visible

If you only record one platform, record iPhone first.

## Resubmission Checklist

- Build a new iPhone archive
- Build a new Mac archive if you submit macOS together
- Upload the new build
- Update Privacy Policy URL in App Store Connect
- Keep the standard Apple EULA in App Store Connect
- Add the standard Terms of Use link to App Description
- Add the review note text
- Attach the screen recording
- Reply to the rejection using the prepared message
- Submit for review again
