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
                    LabeledContent("Fret movement", value: String(result.metrics.totalFretMovement))
                    LabeledContent("Position shifts", value: String(result.metrics.positionShifts))
                    LabeledContent("String changes", value: String(result.metrics.stringChanges))
                    LabeledContent("String skips", value: String(result.metrics.stringSkips))
                    LabeledContent("Open strings", value: String(result.metrics.openStrings))
                    LabeledContent("Average fret", value: cost(result.metrics.averagePhysicalFret))
                    LabeledContent("Maximum fret", value: String(result.metrics.maximumPhysicalFret))
                }

                Section("Profile weights") {
                    weightRow("Fret movement", result.weights.fretMovement)
                    weightRow("Position shift", result.weights.positionShift)
                    weightRow("String change", result.weights.stringChange)
                    weightRow("String skipping", result.weights.stringSkipping)
                    weightRow("Large stretch", result.weights.largeStretch)
                    weightRow("Fret height", result.weights.fretHeight)
                    weightRow("Open-string preference", result.weights.openStringPreference)
                    weightRow("Repeated-note consistency", result.weights.repeatedNoteConsistency)
                    weightRow("Awkward transition", result.weights.awkwardTransition)
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
                        if result.debugLayers.indices.contains(index) {
                            DisclosureGroup("Compare all \(result.debugLayers[index].candidates.count) candidates") {
                                ForEach(result.debugLayers[index].candidates, id: \.position) { candidate in
                                    candidateRow(candidate)
                                }
                            }
                        }
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

    private func weightRow(_ title: String, _ value: Double) -> some View {
        LabeledContent(title, value: cost(value))
            .font(.subheadline)
    }

    private func candidateRow(_ candidate: CandidateEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    "String \(candidate.position.string), fret \(candidate.position.fret)",
                    systemImage: candidate.selected ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(candidate.selected ? .indigo : .primary)
                Spacer()
                if let bestPathCost = candidate.bestPathCost {
                    Text(cost(bestPathCost)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let previous = candidate.bestPreviousPosition {
                Text("Best predecessor: string \(previous.string), fret \(previous.fret)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(candidate.selected ? "Selected minimum-cost route." : (candidate.rejectionReason ?? "Not selected."))
                .font(.caption)
                .foregroundStyle(candidate.selected ? Color.secondary : Color.orange)
            Text("Position cost \(cost(candidate.unary.total)) · incoming \(cost(candidate.incomingTransition?.total ?? 0))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func cost(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
