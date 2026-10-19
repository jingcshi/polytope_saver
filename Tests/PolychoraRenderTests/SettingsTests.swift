import Testing
@testable import PolychoraRender

@Suite struct SettingsTests {
    @Test func targetFPSStepsAreRefreshDivisors() {
        let steps = PolychoraSettings.targetFPSSteps
        #expect(steps == [30, 33, 36, 40, 45, 48, 50, 55, 60, 72, 75, 90, 100, 120, 144, 165, 180])
        #expect(steps[steps.count / 2] == 60)
    }

    @Test func effectiveFPSFallsToNextLowerDivisor() {
        #expect(PolychoraSettings.effectiveFPS(target: 120, refresh: 120) == 120)
        #expect(PolychoraSettings.effectiveFPS(target: 90, refresh: 120) == 60)
        #expect(PolychoraSettings.effectiveFPS(target: 180, refresh: 60) == 60)
        #expect(PolychoraSettings.effectiveFPS(target: 60, refresh: 165) == 55)
        #expect(PolychoraSettings.effectiveFPS(target: 24, refresh: 120) == 24)
        #expect(PolychoraSettings.effectiveFPS(target: 25, refresh: 60) == 20)
    }
}
