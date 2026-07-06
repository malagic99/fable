import SwiftUI

/// The embedded "Trigger Lab": edit a DualSense trigger profile with live
/// preview — as you change a slider, the pad's triggers update so you can feel
/// it. Used for a bottle's default and for a per-game override.
struct TriggerConfigView: View {
    @Binding var profile: TriggerProfile
    @EnvironmentObject private var triggers: DualSenseTriggerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(triggers.isDualSense ? .green : .secondary).frame(width: 8, height: 8)
                Text(L10n.string(triggers.isDualSense ? "trigger.connected" : "trigger.disconnected"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Presets") {
                    ForEach(TriggerProfile.presets, id: \.name) { preset in
                        Button(preset.name) { profile = preset.profile }
                    }
                }
                .fixedSize()
            }

            HStack(alignment: .top, spacing: 16) {
                TriggerEffectPanel(title: "L2", effect: $profile.left, live: triggers.leftValue)
                TriggerEffectPanel(title: "R2", effect: $profile.right, live: triggers.rightValue)
            }
        }
        .onAppear { triggers.preview(profile) }
        .onChange(of: profile) { _, new in triggers.preview(new) }
        // Restore whatever the session had applied (a running game's profile,
        // or off) — closing the config sheet must not kill live triggers.
        .onDisappear { triggers.endPreview() }
    }
}

private struct TriggerEffectPanel: View {
    let title: String
    @Binding var effect: TriggerEffect
    let live: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("trigger.pull", String(Int(live * 100)))).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                ProgressView(value: Double(min(max(live, 0), 1))).tint(live > 0.01 ? .green : .gray)
            }
            Picker("Mode", selection: $effect.mode) {
                ForEach(TriggerMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch effect.mode {
            case .off:
                Text("No resistance.").font(.caption).foregroundStyle(.secondary)
            case .feedback:
                slider("trigger.param.start", $effect.start)
                slider("trigger.param.strength", $effect.strength)
            case .weapon:
                slider("trigger.param.start_wall", $effect.start)
                slider("trigger.param.end_release", $effect.end)
                slider("trigger.param.strength", $effect.strength)
            case .vibration:
                slider("trigger.param.start", $effect.start)
                slider("trigger.param.amplitude", $effect.amplitude)
                slider("trigger.param.frequency", $effect.frequency)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// `label` is an L10n key (the params share strings across effect modes).
    private func slider(_ label: String, _ value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(L10n.string(label)).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }
}
