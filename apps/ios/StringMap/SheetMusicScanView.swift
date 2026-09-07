#if DEBUG
import PhotosUI
import ScorePipeline
import SwiftData
import SwiftUI
import UIKit
import AVFoundation

struct SheetMusicScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    #if DEBUG
    @AppStorage("omrServiceURL") private var debugServiceURL = "http://127.0.0.1:8765"
    #else
    private let debugServiceURL = ""
    #endif
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var jpegData: Data?
    @State private var isCameraPresented = false
    @State private var isCropPresented = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var photoTask: Task<Void, Never>?
    @State private var isRecognizing = false
    @State private var recognitionStatus = ""
    @State private var review: ScanReview?
    @State private var savedDocument: SongDocument?
    @State private var recoveredDocument: SongDocument?
    @State private var errorMessage: String?
    @State private var consent = false
    @State private var draft: ScanDraft?
    @State private var restoredDraft = false
    @State private var cameraDenied = false
    @State private var pitchConvention: MusicXMLPitchConvention = .guitarWritten
    let didImport: (SongDocument) -> Void

    var body: some View {
        List {
            Section {
                Text("Photograph one page of guitar notation. Include the clef, key signature, rhythms, and every stacked note.")
                Text("Use a sharp, evenly lit photo. Crop away other instruments. Handwriting accuracy has not been established; use printed notation.")
                Text("Piano scores, chord names such as G minor, and existing tab are not interpreted.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Your guitar page").eyebrow() }
            Section {
                Button("Take a Photo", systemImage: "camera") { openCamera() }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isRecognizing)
                    .accessibilityIdentifier("scanTakePhoto")
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                    .disabled(isRecognizing).accessibilityIdentifier("scanChoosePhoto")
                if cameraDenied {
                    Link("Allow camera access in Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                    #if targetEnvironment(simulator)
                    Text("Camera capture needs a physical device. Photos works in Simulator.").font(.caption)
                    #else
                    Text("Camera is unavailable on this device. You can choose an existing photo.").font(.caption)
                    #endif
                }
            }
            if let recoveredDocument {
                Section {
                    Text("This page was already saved to your library before the scan closed.")
                    Button("Open saved score", systemImage: "music.note") {
                        didImport(recoveredDocument); dismiss()
                    }.accessibilityIdentifier("scanOpenRecoveredSong")
                }
            }
            if let previewImage, let jpegData {
                Section {
                    Image(uiImage: previewImage).resizable().scaledToFit().frame(maxHeight: 320)
                        .accessibilityLabel("Selected guitar sheet music")
                    Button("Crop, rotate, and straighten", systemImage: "crop.rotate") { isCropPresented = true }.disabled(isRecognizing)
                    LabeledContent("Upload size", value: ByteCountFormatter.string(fromByteCount: Int64(jpegData.count), countStyle: .file))
                    if min(previewImage.size.width, previewImage.size.height) < 900 {
                        Text("This image is small. A sharper, larger photo will preserve staff lines and note heads.").foregroundStyle(.orange)
                    }
                    Picker("Page pitches", selection: $pitchConvention) {
                        Text("Guitar notation").tag(MusicXMLPitchConvention.guitarWritten)
                        Text("Concert pitch").tag(MusicXMLPitchConvention.asEncoded)
                    }.disabled(isRecognizing || draft?.reviewState != nil).accessibilityIdentifier("scanPitchConvention")
                    if draft?.reviewState != nil {
                        Text("Continue note review to change pitches after editing. Your corrections are saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(pitchConvention == .guitarWritten
                         ? "Guitar notation sounds one octave below the written notes. Written E4 becomes sounding E3 for tab and playback."
                         : "Use this for a page written at sounding pitch. No guitar octave is added.")
                        .font(.caption).foregroundStyle(.secondary)
                    if draft?.musicXML != nil {
                        Text("Your recognized notes and unfinished corrections are stored on this device. You can continue reviewing offline.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle("Send this image for recognition", isOn: $consent).disabled(isRecognizing)
                        Text("Only this cropped image is uploaded when you tap Recognize Notes. Images are deleted after processing; unclaimed results expire within one hour. Review the notes before saving.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(draft?.musicXML != nil ? "Continue note review" : (draft != nil ? "Resume recognition" : "Recognize Notes"), systemImage: "waveform.badge.magnifyingglass") { recognize() }
                        .disabled(isRecognizing || (draft?.musicXML == nil && !consent)).accessibilityIdentifier("scanRecognize")
                } header: { Text("Prepare the page").eyebrow() }
            }
            if isRecognizing {
                Section {
                    ProgressView(recognitionStatus)
                    Text("You can cancel at any time. Keep this screen open while the page is processed.").font(.caption)
                    Button("Cancel recognition", role: .cancel) { cancelRecognition(discard: true) }.accessibilityIdentifier("scanCancel")
                }
            }
            if let errorMessage { Section("Needs attention") { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) } }
        }
        .accessibilityIdentifier("scanList")
        .scrollContentBackground(.hidden).background(AmbientBackground())
        .navigationTitle("Scan Sheet Music").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { cancelRecognition(); dismiss() } } }
        .sheet(isPresented: $isCameraPresented) {
            CameraPicker { image in accept(image); isCameraPresented = false } cancelled: { isCameraPresented = false }.ignoresSafeArea()
        }
        .sheet(isPresented: $isCropPresented) {
            if let previewImage { NavigationStack { PageCropView(image: previewImage) { accept($0, preservingPitchConvention: true) } } }
        }
        .sheet(item: $review, onDismiss: {
            if let document = savedDocument {
                savedDocument = nil
                didImport(document)
                dismiss()
            }
        }) { review in
            NavigationStack {
                ScoreReviewView(state: review.state, imageData: review.imageData, persist: { state in
                    guard var value = draft, value.requestID == review.id else { throw CancellationError() }
                    value.reviewState = state
                    try value.save(); draft = value
                }, discard: {
                    guard var value = draft, value.requestID == review.id, let xml = value.musicXML else { throw CancellationError() }
                    let original = try MusicXMLImporter().importScore(from: xml, forReview: true, pitchConvention: value.pitchConvention ?? .asEncoded)
                    value.reviewState = nil; try value.save(); draft = value
                    return ScoreReviewState(score: original)
                }) { xml, score in
                    guard let value = draft, value.requestID == review.id else { throw CancellationError() }
                    let document = try SongDocument.saveReviewedScan(value, score: score, musicXML: xml, in: modelContext)
                    #if DEBUG
                    // Simulate process death after database commit and before
                    // draft deletion; recovery still uses the real disk store.
                    if ProcessInfo.processInfo.environment["STRINGMAP_UI_TEST_RETAIN_COMMITTED_SCAN"] != "1" {
                        try? ScanDraft.clear()
                    }
                    #else
                    try? ScanDraft.clear()
                    #endif
                    draft = nil
                    // Dismiss the review sheet first, then its scan presenter.
                    savedDocument = document
                }
            }
        }
        .task {
            guard !restoredDraft else { return }; restoredDraft = true
            do {
                #if DEBUG
                // UI regression fixture: exercise the ordinary durable-draft
                // review/save flow without pretending a fake recognizer ran.
                let environment = ProcessInfo.processInfo.environment
                if let xml = environment["STRINGMAP_UI_TEST_SCAN_XML_BASE64"].flatMap({ Data(base64Encoded: $0) }),
                   let image = environment["STRINGMAP_UI_TEST_SCAN_IMAGE_BASE64"].flatMap({ Data(base64Encoded: $0) }) {
                    try ScanDraft(requestID: UUID().uuidString, serviceURL: debugServiceURL,
                        sourceName: "UI correction fixture", imageData: image, musicXML: xml).save()
                }
                #endif
                if let saved = try ScanDraft.load() {
                    if let document = try SongDocument.savedScan(requestID: saved.requestID, in: modelContext) {
                        recoveredDocument = document
                        try? ScanDraft.clear()
                        return
                    }
                    draft = saved; jpegData = saved.imageData; previewImage = UIImage(data: saved.imageData); consent = true
                    pitchConvention = saved.pitchConvention ?? .asEncoded
                    recognitionStatus = "Your unfinished page is available to resume."
                }
            } catch { errorMessage = "Could not restore the unfinished scan. You can choose the photo again." }
        }
        .onChange(of: photoItem) { _, item in
            photoTask?.cancel()
            guard let item else { return }
            photoTask = Task {
                do {
                    guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes) else {
                        throw OMRClientError.invalidResponse
                    }
                    guard !Task.isCancelled else { return }; accept(image)
                } catch { if !Task.isCancelled { errorMessage = "Could not read this photo. Choose a JPEG, PNG, or HEIF image." } }
            }
        }
        .onDisappear { cancelRecognition(); photoTask?.cancel() }
    }

    private func openCamera() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            cameraDenied = !allowed; isCameraPresented = allowed
        }
    }
    private func accept(_ image: UIImage, preservingPitchConvention: Bool = false) {
        guard let normalized = image.normalizedScoreJPEG() else { errorMessage = "Could not read this image."; return }
        if let previous = draft, previous.musicXML == nil {
            Task { if let client = try? OMRClient(serviceURL: previous.serviceURL) { await client.delete(id: previous.requestID) } }
        }
        try? ScanDraft.clear(); draft = nil
        previewImage = normalized.image; jpegData = normalized.data; consent = false; review = nil; errorMessage = nil
        recoveredDocument = nil
        if !preservingPitchConvention { pitchConvention = .guitarWritten }
    }
    private func cancelRecognition(discard: Bool = false) {
        recognitionTask?.cancel(); recognitionTask = nil; isRecognizing = false; recognitionStatus = ""
        if discard {
            if let previous = draft {
                Task { if let client = try? OMRClient(serviceURL: previous.serviceURL) { await client.delete(id: previous.requestID) } }
            }
            try? ScanDraft.clear(); draft = nil
        }
    }
    private static func isTerminalRecognitionFailure(_ error: Error) -> Bool {
        if case OMRClientError.service(status: 422, message: _) = error { return true }; return false
    }

    private func recognize() {
        guard let jpegData, consent || draft?.musicXML != nil, !isRecognizing else { return }
        isRecognizing = true; review = nil; errorMessage = nil
        recognitionStatus = draft?.musicXML != nil ? "Preparing saved review…" : "Uploading page…"
        let name = "Guitar page \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        recognitionTask = Task {
            do {
                let existing = draft
                // A recognized page and its corrections are entirely local;
                // resuming them must not depend on hosted-service configuration.
                let serviceURL = try existing.flatMap { $0.musicXML != nil ? $0.serviceURL : nil }
                    ?? AppConfiguration.recognitionURL(debugURL: debugServiceURL)
                var working = existing ?? ScanDraft(requestID: UUID().uuidString, serviceURL: serviceURL, sourceName: name, imageData: jpegData)
                working.pitchConvention = pitchConvention
                if working.serviceURL != serviceURL { working.requestID = UUID().uuidString; working.serviceURL = serviceURL }
                try working.save(); draft = working
                let requestID = working.requestID
                let xml: Data
                if let savedXML = working.musicXML { xml = savedXML }
                else {
                    let client = try OMRClient(serviceURL: working.serviceURL)
                    xml = try await client.recognize(jpegData: jpegData, sourceName: working.sourceName,
                    requestID: working.requestID, resume: existing != nil, received: { data in
                        try Task.checkCancellation()
                        guard var value = draft, value.requestID == requestID else { throw CancellationError() }
                        value.musicXML = data; try value.save(); draft = value
                    }) { state in
                    guard !Task.isCancelled, draft?.requestID == requestID else { return }
                    recognitionStatus = switch state {
                    case .queued: "Waiting for recognition…"
                    case .processing: "Reading notes and rhythms…"
                    case .completed: "Preparing note review…"
                    case .failed: "Recognition failed."
                    case .cancelled: "Recognition cancelled."
                    }
                }
                }
                let convention = working.pitchConvention ?? .asEncoded
                let state: ScoreReviewState
                if let saved = working.reviewState { state = saved }
                else {
                    let score = try await Task.detached(priority: .userInitiated) {
                        try MusicXMLImporter().importScore(from: xml, forReview: true, pitchConvention: convention)
                    }.value
                    state = ScoreReviewState(score: score)
                }
                guard !Task.isCancelled, draft?.requestID == requestID else { return }
                guard !state.score.notes.isEmpty else { throw OMRClientError.service(status: 422, message: "No pitched notes were detected. Try a clearer guitar page.") }
                review = ScanReview(id: requestID, sourceName: working.sourceName, imageData: working.imageData, state: state)
                isRecognizing = false; recognitionTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                isRecognizing = false; recognitionTask = nil; errorMessage = error.localizedDescription
                if error is CancellationError || Self.isTerminalRecognitionFailure(error) {
                    // A terminal engine failure needs a new idempotency key for a retry.
                    if var value = draft { value.requestID = UUID().uuidString; try? value.save(); draft = value }
                }
            }
        }
    }
}

private struct ScanReview: Identifiable {
    let id: String
    let sourceName: String
    let imageData: Data
    let state: ScoreReviewState
}

private struct CameraPicker: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.cancelled()
                return
            }
            parent.captured(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.cancelled()
        }
    }
}

#endif
