# Constellation target layout

The star chart presents up to twelve existing, filtered milestones. It must preserve their ordering, achieved state, detail actions, connecting lines and reduced-motion behavior.

A star's icon and title are one named button with a complete rectangular target of at least44pt. Targets and labels must not overlap at narrow phone widths or larger accessibility text sizes. Use bounded, staggered rows whose column count responds to the actual container width and scaled minimum target width. The chart grows vertically inside the existing scroll view instead of compressing labels or placing new spiral points over existing stars. Titles may use three lines; the full title remains the accessible name.

Acceptance uses deterministic layout bounds/intersection tests plus real iPhone/iPad button frames and original screenshots at normal and accessibility text sizes. Geometry does not establish complete VoiceOver or device integration coverage.
