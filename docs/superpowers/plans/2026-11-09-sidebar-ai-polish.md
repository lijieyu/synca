# Sidebar resizing and AI tutorial polish

User requests: move Pro entitlement to purple badge at tutorial heading; improve iOS tutorial density; bounded resizable desktop sidebars, current widths as minimum. Preserve other accepted screens and pending edits.

- AIPage: heading badge; mobile readable steps, no artificial full-height spacing. Free users may view; backend entitlement remains unchanged.
- Web SidebarFrame: pointer capture, 236–360px, reserve 480px main content, local preference, keyboard arrows/Home/End and double-click reset. Mobile horizontal layout unchanged.
- Mac MessageListView: 220–360pt with main-content guard; drag separator, stored width, adjustable accessibility and double-click reset. Account menu follows sidebar width.
- Verify width clamps/persistence and responsive layout, light/dark tutorial, Web tests/build, native builds. No release requested.

## Outcome
- Implemented both sidebar resize controls and matching account menus. Widths persist locally; responsive shrink preserves the preferred width.
- Web pointer drag (236/360), reload persistence, 800px viewport clamp (320), restore, Home/End/arrow keys, and 390px mobile layout verified in actual browser against isolated mocks.
- 82 Vitest tests and 3 node test suites passed. Web production build, iOS simulator Production and Mac Release builds passed. Native drag behavior still requires device acceptance; no native visual verification claimed.
- AI tutorial uses purple entitlement badge at heading; free users retain view access, backend checks unchanged. Three locales checked at 320/390/600. iOS sheet defaults to 620pt, expands to large, accessibility text sizes use large directly.
- Screenshots are actual H5 responsive pages, not native iOS screenshots. No release or account-data changes.
