# Feed spacing audit and calibration (2026-11-28)

Baseline: `1f8a28ee7dac824faea8060f41726484aba40829`.
Scope: the iOS Feed list and its post rows in `Sources/OneDayApp/FeedView.swift`.
The fixed identity header is excluded. `HubIdentityCapsule.swift`,
`ContentPageHeader.swift`, and chat header files are not to be changed.

## Measurement and target

SwiftUI `List` post rows have a clear background and no explicit row insets;
the visible blank space between adjacent posts is therefore the sum of the
bottom and top row padding, not `listSectionSpacing` (which separates sections).
All dimensions below are points.

| Spacing | Baseline source and value | Standard / rationale | Target |
| --- | --- | --- | --- |
| Post row top inset | `FeedView.swift:678`, `spacingM` = 16 | 8pt grid; compact content-list row inset, one grid unit | 8 |
| Post row bottom inset | `FeedView.swift:678`, `spacingM` = 16 | 8pt grid; same symmetric row inset | 8 |
| Post-to-post gap | emergent: row bottom 16 + next row top 16 = 32; both use `spacingM` | Apple HIG recommends clear grouping/alignment but does not prescribe a numeric feed gap. Material lists favor compact, consistently spaced rows; 8pt grid gives 16 total between rows | 16 total |
| Title to category/body | `FeedView.swift:575`, VStack `spacingS` = 8 | 8pt grid; compact title/supporting-content grouping | 8 |
| Category to body | same VStack `spacingS` = 8 | 8pt grid; one unit within a post | 8 |
| Body to action row | `FeedView.swift:642` adds bottom `spacingM` = 16, plus parent VStack `spacingS` = 8; effective 24 | HIG/Material give no fixed post-body/action value; use nearest compact 8pt-grid step, 8 total | 8 total |
| Truncation / image bottom before next content | `FeedView.swift:652`, `:666`, each `spacingM` = 16 plus parent `spacingS` = 8; effective 24 | No published exact value; 8pt grid nearest compact step | 8 total |
| References bottom before action row | `FeedView.swift:670`, `spacingS` = 8 plus parent `spacingS` = 8; effective 16 | No published exact value; 8pt grid one unit total | 8 total |
| Row-internal action controls | `FeedView.swift:697`, `:731`, `spacingM` = 16 | 8pt grid; leave horizontal control separation unchanged (not part of vertical density issue) | 16 |
| List section spacing | `FeedView.swift:457`, `:520`, `spacingL` = 24 | HIG/Material do not define this page-specific section gap; 8pt-grid 24 retained because it separates list sections, not post rows | 24 |
| Scroll-content top margin | `FeedView.swift:116-121`, `FeedBoard.topClearance`; currently 0 because overlay height is nil; gap argument `spacingS` = 8 | Keep conditional overlap clearance: zero when unobstructed, otherwise measured overlap + 8pt grid unit | 0 now / measured + 8 |
| Scroll-content bottom margin | `FeedView.swift:459`, `:522`, `spacingL` = 24 | Apple HIG: preserve content clearance from screen/system edges; no exact feed number. 8pt grid nearest comfortable end clearance | 24 |
| Page horizontal gutter | `FeedView.swift:312`, `:315`, `pageGutter` = 20 | Apple HIG uses adaptive margins and does not fix a universal feed value; 20pt is the existing content-page gutter and is retained for alignment with the title/filter and other pages | 20 |
| Category chip internal padding | `FeedView.swift:620-625`, horizontal `spacingSM` = 12, vertical `spacingXS` = 4 | No public feed-chip metric; retain compact legibility and existing token | 12 / 4 |

The body/action target is realized by removing redundant bottom paddings; the
existing parent stack contributes the target 8. The same removal on optional
truncation, image, and refs content prevents those paths from reintroducing
extra blank bands. No new spacing token is needed.

## Public design references

- Apple, Human Interface Guidelines, Layout: use consistent alignment and
  spacing, adapt margins to available width, and keep content clear of system
  areas. The guidance does not mandate numeric feed/card gaps:
  <https://developer.apple.com/design/human-interface-guidelines/layout>
- Apple, Human Interface Guidelines, Lists and tables: list content should be
  scannable and rows consistently grouped; no universal numeric inter-row or
  card padding value is prescribed:
  <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>
- Material Design 3, Lists: list items organize related content in consistent
  rows and support compact/dense presentation; exact post-card spacing is not
  specified:
  <https://m3.material.io/components/lists/guidelines>
- Material Design 3, Spacing: 8dp base spacing scale. For this iOS screen the
  analogous 8pt grid is used where public guidance gives no exact value:
  <https://m3.material.io/foundations/layout/understanding-layout/spacing>

## Implementation record

Changed landing points in the resulting file: `FeedView.swift:642` (body
modifier removed, 16 -> 0), `:651` (truncation modifier removed, 16 -> 0),
`:664` (image modifier removed, 16 -> 0), `:667` (refs modifier removed,
8 -> 0), and `:674` (row top/bottom 16 -> 8).
Values-only spacing changes are limited to `FeedView.swift`; no content, row
structure, behavior, identity capsule, or chat header changes are in scope.
