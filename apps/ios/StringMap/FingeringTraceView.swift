import SwiftUI
import FingeringEngine

/// The optimizer's reasoning, made legible. The engine already records every
/// weighted cost and every rejected candidate; the job here is to show which
/// force actually decided each note instead of listing ten numbers per step.
struct FingeringTraceView: View {
    let result: FingeringResult
    @Environment(\.dismiss) private var dismiss
    @State private var showsWeights = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.m) {
                    summary
                    weights
                    Text("Note by note").eyebrow().padding(.top, Space.s)
                    ForEach(Array(result.steps.enumerated()), id: \.element.note.id) { index, step in
                        StepCard(
                            index: index,
                            step: step,
                            layer: result.debugLayers.indices.contains(index) ? result.debugLayers[index] : nil
                        )
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .background(AmbientBackground())
            .navigationTitle("Fingering Explanation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        Bezel {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Profile in use").eyebrow()
                    Text(profileName)
                        .font(.title3.weight(.semibold))
                        .fontWidth(.expanded)
                    Text("Every note below was chosen by one exact minimum-cost path across all valid positions — not note by note in isolation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GradientRule()

                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.m) {
                    metric("Total cost", format(result.totalCost))
                    metric("Movement", String(result.metrics.totalFretMovement))
                    metric("Shifts", String(result.metrics.positionShifts))
                    metric("String changes", String(result.metrics.stringChanges))
                    metric("String skips", String(result.metrics.stringSkips))
                    metric("Open strings", String(result.metrics.openStrings))
                    metric("Average fret", format(result.metrics.averagePhysicalFret))
                    metric("Highest fret", String(result.metrics.maximumPhysicalFret))
                    metric("Difficulty", String(Int(result.metrics.estimatedDifficulty.rounded())))
                }

                GradientRule()

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("What the bars mean").eyebrow()
                    HStack(spacing: Space.m) {
                        key("Movement", Palette.brand)
                        key("Strings", Palette.positionUpcoming)
                    }
                    HStack(spacing: Space.m) {
                        key("Comfort", Palette.positionLocked)
                        key("Position", Palette.neutralData)
                    }
                }
            }
            .padding(Space.l)
        }
    }

    private func key(_ label: String, _ color: Color) -> some View {
        HStack(spacing: Space.xs) {
            Capsule().fill(color).frame(width: 14, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).eyebrow()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private var weights: some View {
        Panel {
            DisclosureGroup(isExpanded: $showsWeights) {
                VStack(spacing: Space.xs) {
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
                .padding(.top, Space.s)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Profile weights").eyebrow()
                    Text("What this profile cares about")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func weightRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(format(value)).font(.caption.monospacedDigit())
        }
    }

    private var profileName: String {
        switch result.profile {
        case let .preset(profile): profile.displayName
        case .custom: "Custom"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Cost model for display

/// Ten raw cost components are accurate but unreadable. They collapse into four
/// forces a player can actually reason about, which is what the bar shows.
private struct CostBuckets {
    let movement: Double
    let stringWork: Double
    let comfort: Double
    let position: Double

    init(step: FingeringStep) {
        let transition = step.transition
        movement = max(0, (transition?.fretMovement ?? 0) + (transition?.positionShift ?? 0))
        stringWork = max(0, (transition?.stringChange ?? 0) + (transition?.stringSkipping ?? 0))
        comfort = max(0, (transition?.largeStretch ?? 0)
            + (transition?.awkwardTransition ?? 0)
            + (transition?.repeatedNoteConsistency ?? 0))
        let unary = step.unary.fretHeight
            + step.unary.openStringPreference
            + step.unary.initialHandPosition
        position = max(0, unary)
        // A position can be rewarded rather than charged — an open string is
        // the usual case. A stacked bar cannot express a negative, and drawing
        // nothing would read as "no reason", so the credit is carried out of
        // the bar and stated in words instead.
        credit = max(0, -unary)
        isOpenString = step.position.fret == 0
    }

    let credit: Double
    let isOpenString: Bool

    var total: Double { movement + stringWork + comfort + position }

    var segments: [(name: String, value: Double, color: Color)] {
        [
            ("Movement", movement, Palette.brand),
            ("String changes", stringWork, Palette.positionUpcoming),
            ("Comfort", comfort, Palette.positionLocked),
            ("Position", position, Palette.neutralData),
        ]
    }

    var dominant: String? {
        segments.filter { $0.value > 0 }.max { $0.value < $1.value }?.name
    }
}

private struct CostBar: View {
    let buckets: CostBuckets

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(buckets.segments.filter { $0.value > 0 }, id: \.name) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: width(for: segment.value, total: geometry.size.width))
                    }
                    if buckets.total <= 0 {
                        Rectangle().fill(Palette.surfaceInset)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }

    private var caption: String {
        if let dominant = buckets.dominant { return "Mostly \(dominant.lowercased())" }
        if buckets.credit > 0 {
            let amount = String(format: "%.2f", buckets.credit)
            return buckets.isOpenString
                ? "Open string — credited \(amount) rather than charged"
                : "Credited \(amount) rather than charged"
        }
        return "No cost — this note is free where it sits"
    }

    private func width(for value: Double, total: CGFloat) -> CGFloat {
        guard buckets.total > 0 else { return 0 }
        return max(2, total * value / buckets.total)
    }
}

// MARK: - Step card

private struct StepCard: View {
    let index: Int
    let step: FingeringStep
    let layer: FingeringDebugLayer?
    @State private var showsCandidates = false

    var body: some View {
        let buckets = CostBuckets(step: step)
        return Panel {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(pitchName(step.note.midi)) · string \(step.position.string), fret \(step.position.fret)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(step.candidateCount) valid position\(step.candidateCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Space.xs)

                    if step.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.positionLocked)
                            .accessibilityLabel("Locked by you")
                    }
                }

                CostBar(buckets: buckets)

                HStack(spacing: Space.l) {
                    labelled("Step", format(step.incrementalCost))
                    labelled("Running", format(step.cumulativeCost))
                    Spacer()
                }

                if let layer, layer.candidates.count > 1 {
                    DisclosureGroup(isExpanded: $showsCandidates) {
                        VStack(spacing: Space.s) {
                            ForEach(layer.candidates, id: \.position) { candidate in
                                CandidateRow(candidate: candidate)
                            }
                        }
                        .padding(.top, Space.s)
                    } label: {
                        Text("Compare all \(layer.candidates.count) positions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.brand)
                    }
                }
            }
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).eyebrow()
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

private struct CandidateRow: View {
    let candidate: CandidateEvaluation

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: candidate.selected ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(candidate.selected ? Palette.brand : Palette.positionRejected)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("String \(candidate.position.string), fret \(candidate.position.fret)")
                        .font(.caption.weight(candidate.selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let bestPathCost = candidate.bestPathCost {
                        Text(String(format: "%.2f", bestPathCost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(candidate.selected
                    ? "Cheapest complete route through this note."
                    : (candidate.rejectionReason ?? "Not selected."))
                    .font(.caption2)
                    .foregroundStyle(candidate.selected ? Color.secondary : Palette.positionLocked)
                    .fixedSize(horizontal: false, vertical: true)

                if let previous = candidate.bestPreviousPosition {
                    Text("Best route in: string \(previous.string), fret \(previous.fret)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Space.s)
        .background(
            candidate.selected ? Palette.brand.opacity(0.07) : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
