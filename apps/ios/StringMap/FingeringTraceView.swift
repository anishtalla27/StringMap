import SwiftUI
import FingeringEngine

struct FingeringTraceView: View {
    let result: FingeringResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Profile", value: profileName)
                    LabeledContent("Total ergonomic cost", value: cost(result.totalCost))
                    LabeledContent("Position shifts", value: String(result.metrics.positionShifts))
                    LabeledContent("String changes", value: String(result.metrics.stringChanges))
                    LabeledContent("Average fret", value: cost(result.metrics.averagePhysicalFret))
                }

                ForEach(Array(result.steps.enumerated()), id: \.element.note.id) { index, step in
                    Section("\(index + 1). MIDI \(step.note.midi) · String \(step.position.string), fret \(step.position.fret)") {
                        LabeledContent("Valid positions", value: String(step.candidateCount))
                        costRow("Fret movement", step.transition?.fretMovement ?? 0)
                        costRow("Position shift", step.transition?.positionShift ?? 0)
                        costRow("String change", step.transition?.stringChange ?? 0)
                        costRow("String skipping", step.transition?.stringSkipping ?? 0)
                        costRow("Large stretch", step.transition?.largeStretch ?? 0)
                        costRow("Repeated-note consistency", step.transition?.repeatedNoteConsistency ?? 0)
                        costRow("Awkward transition", step.transition?.awkwardTransition ?? 0)
                        costRow("Fret height", step.unary.fretHeight)
                        costRow("Open-string preference", step.unary.openStringPreference)
                        costRow("Initial hand position", step.unary.initialHandPosition)
                        if step.isLocked { Label("Locked by user", systemImage: "lock.fill").foregroundStyle(.indigo) }
                        LabeledContent("Incremental", value: cost(step.incrementalCost))
                        LabeledContent("Cumulative", value: cost(step.cumulativeCost))
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Fingering Explanation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var profileName: String {
        switch result.profile {
        case let .preset(profile): profile.displayName
        case .custom: "Custom"
        }
    }

    private func costRow(_ title: String, _ value: Double) -> some View {
        LabeledContent(title, value: cost(value))
    }

    private func cost(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
