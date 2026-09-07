public extension FingeringProfile {
    var weights: CostWeights {
        switch self {
        case .beginner:
            CostWeights(
                fretMovement: 1.1, positionShift: 2.4, stringChange: 0.9,
                largeStretch: 4.8, fretHeight: 0.5, openStringPreference: 3.5,
                comfortableStretch: 3, stringSkipping: 1.5,
                repeatedNoteConsistency: 2.0, initialHandPosition: 1.5,
                awkwardTransition: 2.5
            )
        case .balanced:
            CostWeights(
                fretMovement: 1.4, positionShift: 2.8, stringChange: 1.35,
                largeStretch: 3.2, fretHeight: 0.2, openStringPreference: 1.2,
                comfortableStretch: 4, stringSkipping: 1.1,
                repeatedNoteConsistency: 2.4, initialHandPosition: 0.7,
                awkwardTransition: 1.8
            )
        case .stayInPosition:
            CostWeights(
                fretMovement: 2.4, positionShift: 7.0, stringChange: 1.6,
                largeStretch: 5.0, fretHeight: 0.05, openStringPreference: 0.25,
                comfortableStretch: 4, stringSkipping: 1.2,
                repeatedNoteConsistency: 3.0, initialHandPosition: 3.0,
                awkwardTransition: 2.0
            )
        case .minimumMovement:
            CostWeights(
                fretMovement: 3.2, positionShift: 4.0, stringChange: 0.45,
                largeStretch: 2.0, fretHeight: 0.08, openStringPreference: 0.1,
                comfortableStretch: 5, stringSkipping: 0.35,
                repeatedNoteConsistency: 3.5, initialHandPosition: 1.0,
                awkwardTransition: 1.0
            )
        case .performance:
            CostWeights(
                fretMovement: 1.2, positionShift: 2.0, stringChange: 1.8,
                largeStretch: 2.3, fretHeight: 0.03, openStringPreference: -0.25,
                comfortableStretch: 5, stringSkipping: 1.6,
                repeatedNoteConsistency: 1.8, initialHandPosition: 0.2,
                awkwardTransition: 0.8
            )
        }
    }
}
