import Foundation
import Testing
@testable import Fable

/// Hardware detection parsing + the hardware-aware performance matrix.
@Suite struct HardwareProfileTests {

    private func profile(
        chip: String, memoryGB: Int, gpu: Int? = nil
    ) -> HardwareProfile {
        HardwareProfile(
            chipName: chip, modelIdentifier: "Mac16,8",
            memoryBytes: Int64(memoryGB) * 1_073_741_824,
            performanceCores: 8, efficiencyCores: 4, gpuCores: gpu
        )
    }

    @Test
    func chipTierParsesRealBrandStrings() {
        #expect(HardwareProfile.tier(fromBrand: "Apple M1") == .base)
        #expect(HardwareProfile.tier(fromBrand: "Apple M4 Pro") == .pro)
        #expect(HardwareProfile.tier(fromBrand: "Apple M2 Max") == .max)
        #expect(HardwareProfile.tier(fromBrand: "Apple M1 Ultra") == .ultra)
        #expect(HardwareProfile.tier(fromBrand: "Intel(R) Core(TM) i7-9750H") == .other)
    }

    @Test
    func memoryRoundsToMarketingGB() {
        #expect(profile(chip: "Apple M4 Pro", memoryGB: 24).memoryGB == 24)
        // Real-world sysctl value for 24 GB.
        var p = profile(chip: "Apple M4 Pro", memoryGB: 0)
        p.memoryBytes = 25_769_803_776
        #expect(p.memoryGB == 24)
    }

    @Test
    func summaryReadsLikeASpecLine() {
        let p = profile(chip: "Apple M4 Pro", memoryGB: 24, gpu: 16)
        #expect(p.summary == "Apple M4 Pro · 24 GB · 8P+4E · 16-core GPU")
    }

    @Test
    func detectionOnThisMachineReturnsSomethingReal() {
        // Smoke test on real hardware: apple silicon or intel, memory > 0.
        let current = HardwareProfile.detect()
        #expect(current.memoryBytes > 0)
        #expect(!current.chipName.isEmpty)
    }

    // MARK: Hardware-aware recommendations

    @Test
    func proClassMachineGetsSteady60PlusMetalFX() {
        // The user's actual machine: M4 Pro, 24 GB.
        let m4pro = profile(chip: "Apple M4 Pro", memoryGB: 24)
        let rec = PerformanceOptions.recommended(for: .sikarugir, hardware: m4pro)
        #expect(rec.frameRateCap == 60)
        #expect(rec.metalFXUpscaling)
    }

    @Test
    func bigMachinesGetHeadroom() {
        let m2max = profile(chip: "Apple M2 Max", memoryGB: 64)
        let rec = PerformanceOptions.recommended(for: .sikarugir, hardware: m2max)
        #expect(rec.frameRateCap == 120)
        #expect(!rec.metalFXUpscaling)
        #expect(PerformanceOptions.recommended(for: .dxmt, hardware: m2max).frameRateCap == 120)
    }

    @Test
    func maxChipWithModestMemoryStaysSteady() {
        // Chip tier alone isn't headroom — 32 GB Max still shares with the GPU.
        let m1max32 = profile(chip: "Apple M1 Max", memoryGB: 32)
        let rec = PerformanceOptions.recommended(for: .gptk, hardware: m1max32)
        #expect(rec.frameRateCap == 60)
        #expect(rec.metalFXUpscaling)
    }

    @Test
    func untunedBackendsStayUntouchedRegardlessOfHardware() {
        let beast = profile(chip: "Apple M3 Ultra", memoryGB: 192)
        #expect(PerformanceOptions.recommended(for: .off, hardware: beast) == PerformanceOptions())
        #expect(PerformanceOptions.recommended(for: .crossover, hardware: beast) == PerformanceOptions())
        #expect(PerformanceOptions.hardwareAdvice(for: .off, hardware: beast) == nil)
    }

    @Test
    func adviceNamesTheActualMachine() {
        let m4pro = profile(chip: "Apple M4 Pro", memoryGB: 24)
        let advice = PerformanceOptions.hardwareAdvice(for: .sikarugir, hardware: m4pro)
        #expect(advice?.contains("Apple M4 Pro") == true)
        #expect(advice?.contains("24") == true)
    }
}
