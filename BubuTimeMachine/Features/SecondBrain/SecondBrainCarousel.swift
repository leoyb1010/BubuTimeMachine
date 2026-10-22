import SwiftUI

extension View {
    /// For a horizontal `ScrollView` sitting inside `inset` points of padding: lets the scroll area run to the
    /// container's edge while the first/last item still line up with the content (no square cut at the margin).
    /// `clips: false` (page-level rows) also lets shadows and the next card bleed past the column edge.
    func secondBrainCarouselBleed(_ inset: CGFloat, clips: Bool = true) -> some View {
        contentMargins(.horizontal, inset, for: .scrollContent)
            .padding(.horizontal, -inset)
            .scrollClipDisabled(!clips)
    }
}
