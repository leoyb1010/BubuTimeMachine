import Testing
@testable import BubuTimeMachine

struct SchoolVisualValueTests {
    @Test func mealRingsNeverTurnMissingOrAmbiguousAmountsIntoZero() {
        #expect(SchoolVisualValue.fraction("90%") == 0.9)
        #expect(SchoolVisualValue.fraction("100％") == 1)
        #expect(SchoolVisualValue.fraction("0%") == 0)
        for value in ["", "未记录", "半碗", "90%或80%", "101%", "-5%", "90"] {
            #expect(SchoolVisualValue.fraction(value) == nil)
        }
    }
    @Test func napBandUsesOnlyAnExplicitValidTimeRange() {
        let nap = SchoolVisualValue.nap("12:17–14:30")
        #expect(nap?.minutes == 133)
        #expect(nap?.start == "12:17")
        #expect(nap?.end == "14:30")
        #expect(SchoolVisualValue.nap("12时17分 到 14时30分")?.minutes == 133)
        for value in ["安静", "12:75–14:30", "14:30–12:17", "昨晚20:00至今天08:00", "12:17–14:30 或 13:00–14:00"] {
            #expect(SchoolVisualValue.nap(value) == nil)
        }
    }
}
