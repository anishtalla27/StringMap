import SwiftUI
import FingeringEngine

struct SettingsView: View {
    @AppStorage("defaultProfile") private var profileRaw = FingeringProfile.balanced.rawValue
    @AppStorage("defaultTuning") private var tuningRaw = GuitarTuningPreset.standard.rawValue
    @AppStorage("defaultCapo") private var capo = 0
    @AppStorage("defaultFrets") private var frets = 20
    @AppStorage("leftHanded") private var leftHanded = false
    @AppStorage("defaultMetronome") private var metronome = false
    #if DEBUG
    @AppStorage("enableScanPreview") private var scanEnabled = FeatureFlags.scanEnabledByDefault
    @AppStorage("omrServiceURL") private var omrServiceURL = "http://127.0.0.1:8765"
    #endif

    var body: some View {
        Form {
            Section {
                Picker("Tuning", selection: $tuningRaw) {
                    ForEach(GuitarTuningPreset.allCases.filter { $0 != .custom }, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
                Stepper(value: $capo, in: 0...12) {
                    LabeledContent("Capo") {
                        Text(capo == 0 ? "None" : "Fret \(capo)").stableNumber(.body)
                    }
                }
                Stepper(value: $frets, in: 12...30) {
                    LabeledContent("Frets") { Text("\(frets)").stableNumber(.body) }
                }
                Toggle("Left-handed fretboard", isOn: $leftHanded)
            } header: {
                Text("Instrument defaults").eyebrow()
            } footer: {
                Text("Applied to new Free Practice exercises. Saved exercises keep their own settings. Tutorial Mode uses standard tuning with no capo.")
            }
            .listRowBackground(Palette.surfaceRaised)

            Section {
                Picker("Default profile", selection: $profileRaw) {
                    ForEach(FingeringProfile.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
                Toggle("Metronome by default", isOn: $metronome)
            } header: {
                Text("Arrangement and practice").eyebrow()
            }
            .listRowBackground(Palette.surfaceRaised)

            #if DEBUG
            Section {
                Toggle("Sheet music scanning", isOn: $scanEnabled)
                if scanEnabled {
                    TextField("Recognition service URL", text: $omrServiceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
            } header: {
                Text("Developer preview").eyebrow()
            } footer: {
                Text("Internal experiment only. Scanning is not included in App Store builds.")
            }
            .listRowBackground(Palette.surfaceRaised)

            #endif

            Section {
                LabeledContent("Tab and playback", value: "On device, offline")
                LabeledContent("Score renderer", value: "alphaTab")
                LabeledContent("Analytics", value: "None")
                LabeledContent("Accounts", value: "None")
                NavigationLink("Privacy policy") { LegalDocumentView(name: "privacy", title: "Privacy Policy", publicURL: AppConfiguration.privacyURL) }
                NavigationLink("Support") { LegalDocumentView(name: "support", title: "Support", publicURL: AppConfiguration.supportURL) }
                NavigationLink("Licenses and acknowledgements") { LegalDocumentView(name: "licenses", title: "Licenses", publicURL: nil) }
            } header: {
                Text("Privacy").eyebrow()
            } footer: {
                Text("Exercises, saved music, and practice settings stay on this device. No advertising, analytics, or music uploads.")
            }
            .listRowBackground(Palette.surfaceRaised)

            Section {
                LabeledContent("Version") { Text(Self.version).stableNumber(.body) }
                LabeledContent("Build") { Text(Self.build).stableNumber(.body) }
            } header: {
                Text("About").eyebrow()
            }
            .listRowBackground(Palette.surfaceRaised)
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Settings")
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
