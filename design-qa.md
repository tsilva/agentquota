# AgentQuota Design QA

## Comparison Target

- Source visual truth: `docs/reference/codex-weekly-quota-widget.png`
- Rendered implementation: `docs/qa/agentquota-implementation.png`
- Combined comparison: `docs/qa/agentquota-design-comparison.png`
- Viewport: native macOS SwiftUI menu-extra content at 350 × 199 points in dark appearance.
- State: connected Codex Pro account, one weekly quota window, 41% used / 59% remaining, reset in 3 days 17 hours, updated now.
- Source dimensions: 1536 × 1024 pixels; the compared popover crop is 466 × 488 pixels with no embedded density metadata.
- Implementation dimensions: 700 × 398 pixels at 144 ppi (`@2x`), corresponding to 350 × 199 native points. For the combined evidence, the implementation was downsampled to 466 × 265 pixels, then top-aligned on a 466 × 488 canvas beside the source crop. This normalizes content width while retaining the source's extra forecast region.
- CSS size / device scale factor: not applicable to this native AppKit/SwiftUI app; native point size and backing scale are recorded above instead.

## Findings

No actionable P0, P1, or P2 differences remain.

The reference's wider forecast block (`Runs out…` and consumption rate) is intentionally absent because those inferred values are outside the v1 plan. The implementation preserves the reference hierarchy while using the required remaining-quota semantics, plan/connection status, relative and local reset times, and connection recovery model.

### Required Fidelity Surfaces

- Fonts and typography: the implementation uses the native macOS system family with semibold title/value hierarchy, secondary small text, monospaced digits for changing quota times, and no visible clipping or wrapping.
- Spacing and layout rhythm: the 20-point inset, grouped header, quota row, separator, and update footer match the source's compact vertical rhythm. Rounded dark material is retained by the native menu-extra surface.
- Colors and visual tokens: the final capture uses a dark translucent surface, high-contrast white hierarchy, secondary gray metadata, green connected state, and a blue rounded progress treatment matching the reference.
- Image quality and asset fidelity: the popover has no raster imagery or bespoke brand marks. Controls use sharp native SF Symbols; no emoji, placeholder art, inline SVG, or code-drawn substitute image is present.
- Copy and content: visible copy is coherent in isolation and follows the implementation plan where it intentionally differs from the sample screenshot (`Weekly quota`, `59% remaining`, connection state, relative reset, local reset, and last-updated time).

## Full-View Comparison Evidence

`docs/qa/agentquota-design-comparison.png` places the source popover crop and final rendered SwiftUI popover together in one image. It verifies composition, hierarchy, progress treatment, dark surface, spacing, reset metadata, icon placement, and footer treatment.

## Focused Region Evidence

No additional focused crop was needed: the combined image is already a tight popover-only crop, and all typography, icons, progress geometry, dividers, and reset/update metadata remain readable at its saved resolution.

## Comparison History

1. Initial combined comparison found two P2 fidelity issues: the native progress control rendered neutral gray instead of the source's blue treatment, and the gear menu displayed a trailing indicator while duplicating connection status in the footer.
2. Fixes applied in `MenuBarContentView`: replaced the inactive-looking progress rendering with an accessible rounded blue progress track, hid the menu indicator, labeled the window `Weekly quota`, and removed the redundant footer connection label.
3. Post-fix evidence: `docs/qa/agentquota-design-comparison.png` shows the corrected blue progress treatment, single gear icon, source-aligned quota label, and cleaner update footer. No actionable P0/P1/P2 difference remains.

## Open Questions

None. The source's predictive exhaustion copy is treated as illustrative rather than a v1 requirement, as directed by `PLAN.md`.

## Implementation Checklist

- [x] Match the source's compact dark popover hierarchy.
- [x] Preserve required remaining-percentage semantics.
- [x] Match progress color, radius, and visual weight.
- [x] Use native menu and refresh controls with accessible labels.
- [x] Keep reset and update metadata readable without clipping.

## Follow-up Polish

- P3 residual test gap: the menu-bar label itself could not be captured while macOS was locked. Its implementation uses the planned terminal symbol, tightest remaining percentage, em dash loading state, and stale warning; the popover component is the visually compared target.

final result: passed

---

# Adaptive Menu-Bar Meter Design QA

## Comparison Target

- Source visual truth: the user-provided 94% status-item screenshot, preserved as the focused crop `docs/qa/agentquota-menu-meter-adaptive-source.png`, together with the explicit request to reclaim the unused `100%` digit column.
- Rendered implementation: `docs/qa/agentquota-menu-meter-adaptive-implementation.png`.
- Combined comparison: `docs/qa/agentquota-menu-meter-adaptive-comparison.png` (source before state on the left, adaptive implementation on the right).
- Viewport: native AppKit status-item image. The implementation is 39 × 19 points at 94%; the previous maximum footprint remains 44 × 19 points at 100% and while loading.
- State: fresh quota snapshot at 94% remaining.
- Source dimensions: 136 × 60 pixels at 144 ppi; the focused visible meter crop is 83 × 26 pixels.
- Implementation dimensions: 78 × 38 pixels at 144 ppi (`@2x`), corresponding to 39 × 19 native points.
- CSS size / device scale factor: not applicable to this native AppKit component. The comparison normalizes both focused artifacts to 216 pixels high and preserves their aspect ratios.

## Findings

No actionable P0, P1, or P2 differences remain.

The adaptive render removes the blank digit-sized gap visible between `>_` and `94%` and shortens the progress track by the same reclaimed width. Two-digit percentages now use a 39-point image and one-digit percentages use 33 points; `100%` and the loading state retain the original 44-point maximum so neither clips.

### Required Fidelity Surfaces

- Fonts and typography: the existing native 9-point monospaced prompt and monospaced-digit value fonts, weights, baseline, and antialiasing are unchanged. The prompt/value gap now stays at the intended 1.5 points instead of expanding by the missing digit column.
- Spacing and layout rhythm: the value is laid out at its intrinsic width, and the image plus progress track reclaim only unused whole-point width. Outer balance and the 19-point menu-bar height remain unchanged.
- Colors and visual tokens: semantic label color, muted track, system-blue fill, and stale orange remain unchanged.
- Image quality and asset fidelity: the implementation is rendered directly from the production AppKit bitmap drawing code at the native backing scale. There are no raster substitutes, decorative assets, or approximated icons.
- Copy and content: the meter still shows the literal terminal prompt and exact remaining percentage; loading, stale, tooltip, and accessibility copy are unchanged.

## Full-View Comparison Evidence

`docs/qa/agentquota-menu-meter-adaptive-comparison.png` places the original 94% meter and revised production render side by side at equal height. It shows the removed blank digit column, tighter overall silhouette, and proportionally shorter progress treatment without changing the established typography or color hierarchy.

## Focused Region Evidence

The meter is itself the focused region and fills the comparison image. Prompt/value spacing, baseline, progress inset, line weight, fill proportion, and overall width are all readable, so a second crop is unnecessary.

## Comparison History

1. The supplied source screenshot exposed one P2 density issue: the fixed 44-point `100%` value slot left a digit-sized blank gap at 94%, while the progress track and status-item image kept their maximum width.
2. The implementation now sizes the image from the displayed digit count and lays out the percentage at its intrinsic width. Tests cover two-digit, one-digit, 100%, loading, and stale states.
3. Post-fix evidence in `docs/qa/agentquota-menu-meter-adaptive-comparison.png` shows a 10-pixel reduction in the visible 94% component at `@2x`, the intended compact prompt/value gap, and no clipping or alignment regression.

## Open Questions

None.

## Implementation Checklist

- [x] Reclaim the unused third digit column below 100%.
- [x] Reclaim both unused digit columns for one-digit percentages.
- [x] Keep 100% and loading states at the safe maximum width.
- [x] Shorten the progress track with the status-item image.
- [x] Preserve height, typography, colors, stale state, tooltip, and accessibility behavior.

## Follow-up Polish

No remaining P3 visual refinements were identified in the focused component comparison.

final result: passed

---

# Borderless Menu-Bar Meter Design QA

## Comparison Target

- Source visual truth: `docs/reference/agentquota-menu-meter-borderless-concept.png`
- Source focused crop: `docs/qa/agentquota-menu-meter-borderless-source-crop.png`
- Rendered implementation: `docs/qa/agentquota-menu-meter-borderless-implementation.png`
- Combined comparison: `docs/qa/agentquota-menu-meter-borderless-comparison.png`
- Viewport: native AppKit status-item image at 44 × 19 points in dark appearance.
- State: fresh quota snapshot at 88% remaining, matching the selected mock.
- Source dimensions: 1914 × 822 pixels. The selected meter was cropped to 90 × 40 pixels and normalized to 342 × 152 pixels.
- Implementation dimensions: 352 × 152 pixels, rendered directly from the production `MenuBarQuotaMeter` drawing code at 8× its 44 × 19-point footprint.
- CSS size / device scale factor: not applicable to this native AppKit component. The focused comparison normalizes both artifacts to 152 pixels high while preserving their aspect ratios.

## Findings

No actionable P0, P1, or P2 differences were found in the first comparison pass.

The implementation matches the selected borderless structure: native terminal text and percentage on one baseline, no enclosing shape or background, and a single quiet proportional progress line below. The component retains a fixed footprint while the percentage and fill change.

### Required Fidelity Surfaces

- Fonts and typography: native 9-point monospaced system and monospaced-digit fonts match the mock's compact developer-tool character, maintain percentage alignment, and render without clipping.
- Spacing and layout rhythm: the 44 × 19-point footprint aligns with neighboring menu-bar symbols. A 1.5-point prompt/value gap and two-point progress inset keep the item compact without crowding.
- Colors and visual tokens: semantic macOS label color keeps text native across appearances. The muted label-color track and system-blue 88% fill reproduce the reference hierarchy; stale data switches both text and fill to semantic orange.
- Image quality and asset fidelity: the component is resolution-independent native AppKit UI. There are no raster assets, decorative marks, logos, or substitute imagery in the selected meter; the terminal prompt is literal UI content.
- Copy and content: the compared state exactly shows `>_ 88%`. Loading remains `>_ —`, and stale data retains the existing warning semantics without changing layout.

## Full-View Comparison Evidence

`docs/qa/agentquota-menu-meter-borderless-comparison.png` places the selected focused mock and production render together at the same height. It verifies the borderless silhouette, terminal/value hierarchy, component density, underline placement, and proportional blue fill.

## Focused Region Evidence

The menu-bar meter is itself the focused region and fills the comparison image. Its type weight, baseline, prompt/value spacing, underline thickness, track contrast, and 88% state are readable at the saved 8× scale, so no additional crop is needed.

## Comparison History

1. First-pass evidence in `docs/qa/agentquota-menu-meter-borderless-comparison.png` found no actionable P0/P1/P2 mismatch. No visual correction loop was required.

## Open Questions

None.

## Implementation Checklist

- [x] Remove the enclosing rectangle and filled background.
- [x] Keep `>_` and the percentage on one compact baseline.
- [x] Add a thin full-width track with proportional blue progress.
- [x] Preserve a fixed footprint through `100%`, loading, and stale states.
- [x] Preserve tooltip and accessibility descriptions.

## Follow-up Polish

No remaining P3 visual refinements were identified in the focused component comparison.

final result: passed

---

# Compact Menu-Bar Meter Design QA

## Comparison Target

- Source visual truth: `docs/reference/agentquota-menu-meter-concept.png`
- Source focused crop: `docs/qa/agentquota-menu-meter-source-crop.png`
- Rendered implementation: `docs/qa/agentquota-menu-meter-implementation.png`
- Combined comparison: `docs/qa/agentquota-menu-meter-comparison.png`
- Viewport: native AppKit status-item image at 48 × 19 points in dark appearance.
- State: fresh quota snapshot at 100% remaining, matching the selected mock.
- Source dimensions: 1536 × 1024 pixels. The meter was cropped to 240 × 98 pixels and normalized to 372 × 152 pixels.
- Implementation dimensions: 384 × 152 pixels, rendered directly from the production `MenuBarQuotaMeter` drawing code at 8× its 48 × 19-point footprint.
- CSS size / device scale factor: not applicable to this native AppKit component. The focused comparison normalizes both artifacts to 152 pixels high while preserving their aspect ratios.

## Findings

No actionable P0, P1, or P2 differences remain.

The production meter preserves the selected compact proportions, terminal prompt inside the fill, fixed-width `100%` slot, battery-weight outline, inset dark gap, sharper corners, and full blue track at 100%. At lower values, only the blue fill width changes; the component and text positions remain stable.

### Required Fidelity Surfaces

- Fonts and typography: native monospaced system and monospaced-digit fonts preserve the CLI character and prevent percentage-width jitter. The 9-point semibold/medium treatment remains readable without clipping.
- Spacing and layout rhythm: the 48 × 19-point frame matches the mock's compact aspect ratio. The 1.3-point border and 2.5-point track inset reproduce the battery-like border and inner margin, while the fixed text slot keeps `100%` inside the track.
- Colors and visual tokens: the meter uses semantic macOS label white, system blue, and orange for stale data, retaining contrast across system appearances.
- Image quality and asset fidelity: the implementation is resolution-independent AppKit drawing, so the border, fill, clipping, and typography remain sharp at native backing scales. The CLI mark is rendered as native monospaced text because it is the meter's literal content rather than a decorative image asset.
- Copy and content: the focused state exactly shows `>_ 100%`. Loading uses an em dash and stale data uses the existing warning semantics without changing the meter footprint.

## Full-View Comparison Evidence

`docs/qa/agentquota-menu-meter-comparison.png` places the selected meter crop and the production render together at the same visual height. It verifies overall width-to-height ratio, outline weight, corner sharpness, blue fill, internal gap, and text placement.

## Focused Region Evidence

The meter itself is the focused region and fills the comparison image, so no additional crop is needed. Border, inset, glyph spacing, percentage alignment, and corner geometry are all readable at 8× scale.

## Comparison History

1. The first production render exposed a P2 compactness mismatch: a 60 × 19-point frame and 10.5/11-point text made the meter wider and more crowded than the selected mock.
2. The implementation was tightened to 48 × 19 points, text was reduced to 9 points, prompt spacing to 1.5 points, and the outer radius to 2 points.
3. Post-fix evidence in `docs/qa/agentquota-menu-meter-comparison.png` shows the corrected compact ratio, sharper corners, balanced internal spacing, and battery-weight border. No actionable P0/P1/P2 difference remains.

## Open Questions

None.

## Implementation Checklist

- [x] Keep the CLI prompt inside the progress meter.
- [x] Size the frame only for the prompt plus `100%`.
- [x] Match the selected sharper corner treatment.
- [x] Match the battery-like outline and inner margin.
- [x] Keep width and text alignment stable from loading through 100%.
- [x] Preserve stale-state warning and accessibility descriptions.

## Follow-up Polish

No remaining P3 visual refinements were identified in the focused component comparison.

final result: passed
