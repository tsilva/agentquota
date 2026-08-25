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
