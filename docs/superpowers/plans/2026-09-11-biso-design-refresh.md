# BISO app design refresh

The app should feel like a campus companion with BISO's own identity. Use navy
`#001731`, blue `#3DA9E0`, white `#FFFFFF`, paper `#F4F7FA`, muted ink `#526579`,
and dark surface `#102C46`. Museo Sans 300 is available in BISO Sites; bundle the
actual font, with system fallbacks for unsupported glyphs.

Home: a photographic campus cover, clear campus selection and notifications,
image-led events, compact shop items, and readable opportunity rows. Explore:
a directory with generous row spacing instead of identical rainbow cards.
Profile: a navy membership-style header and quiet grouped settings.

Glass belongs to floating chrome. Keep content in Flutter with opaque surfaces.
Use `native_liquid_glass_flutter` behind a BISO adapter for native iOS material
and a solid Material fallback elsewhere. Remove `liquid_glass_widgets` and its
global shader initialization. Native rendering still needs device profiling;
do not claim a frame-rate improvement from architecture alone.

The shell overlays navigation on a full-height viewport. BisoNavigationInset
provides stable trailing scroll padding, including the home indicator, so content
runs behind the glass and the final item scrolls completely above it. This inset
belongs once at the end of a list, never inside each card or around a viewport.
Fixed purchase, expense and chat controls also receive navigation clearance.
Downward scrolling collapses navigation into the active tab at the trailing
corner; upward scrolling or tapping expands it. Ignore horizontal carousels and
bounce. Reset on route changes, hide with the keyboard, and honor reduced motion
and accessible navigation. The bar's native material has no extra Flutter stroke
or colored tint ring.

Search expands across the existing header on Explore, Events and Shop. Explore
filters its directory; Events and Shop retain their server-backed queries. Closing
clears the query and cancels pending debounce work. There is no history or extra
search row. Labels are localized in English and Norwegian.

Implementation and verification:

- [x] Add navigation regression tests for collapse, reverse, tap, horizontal
  scrolling, route changes, safe-area clearance, keyboard and accessibility.
- [x] Implement shared navigation and native material adapter; remove shaders.
- [x] Bundle Museo Sans and unify light/dark theme, cards, controls and headers.
- [x] Restyle Home, Explore and Profile while retaining routes and data sources.
- [x] Run focused tests, existing tests, analyzer and an iOS simulator build.
- [x] Inspect simulator screenshots and document physical-device profiling limits.

Existing uncommitted version bump `2.2.1+85` belongs to the user and is preserved.


Verification after screenshot feedback (2026-09-11): the navigation tests now
assert the full-height viewport, content behind the compact bar, and end-of-list
clearance. Real-screen regressions cover order-card heights, final-order clearance,
and the marketplace chat composer's position and ability to receive focus.
Search tests cover expansion without moving content, input focus, query debounce,
closing/cancellation, enlarged text and reduced motion.

Native material was inspected on the iOS 26.5 simulator over Home and Explore
content: underlying text is visibly softened through the bar. Explore's expanding
search and filtering were exercised in the simulator. Simulator gesture automation
still did not move lists, so collapse/expand gestures and end-of-list geometry are
verified by Flutter tests, not claimed as a physical-device interaction test.

Android's solid Material fallback is covered by widget tests, but an APK could
not be built because this machine has no Android SDK. Before release, profile
scrolling and native-view composition in profile mode on physical iPhones,
including the oldest supported device, and verify Reduce Transparency and VoiceOver.
No frame-time or battery improvement is claimed without those measurements.

Only the Museo Sans 300 font file was present in BISO Sites. It is bundled as
weight 300; no other font weights have been fabricated or downloaded.
