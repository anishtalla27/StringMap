#if DEBUG
import SwiftUI
import CoreImage.CIFilterBuiltins
import Vision

/// Four corners are in image coordinates, never screen pixels. Core Image's
/// perspective transform rectifies both camera photos and library selections.
struct PageCropView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage
    @State private var corners: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
    @State private var error: String?
    let accept: (UIImage) -> Void

    init(image: UIImage, accept: @escaping (UIImage) -> Void) { _image = State(initialValue: image); self.accept = accept }

    var body: some View {
        VStack(spacing: 20) {
            Text("Drag the four corners around the guitar staff or page. Keep clefs, key signatures, and all notes inside.")
                .font(.callout).padding(.horizontal)
            GeometryReader { proxy in
                let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                    Path { path in
                        let points = corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        path.addLines(points); path.closeSubpath()
                    }.stroke(Palette.brand, lineWidth: 2)
                    ForEach(0..<4, id: \.self) { i in
                        CropHandle(point: $corners[i], size: size,
                            label: ["Top left corner", "Top right corner", "Bottom right corner", "Bottom left corner"][i])
                    }
                }
                .coordinateSpace(name: "crop")
                .frame(width: proxy.size.width, height: proxy.size.height)
            }.padding(20)
            HStack {
                Button("Rotate 90°", systemImage: "rotate.right") { image = image.rotatedClockwise(); reset() }
                Spacer()
                Button("Full image") { reset() }
                Button("Detect page") { detect() }
            }.padding(.horizontal).buttonStyle(.borderless)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Button("Use this crop") {
                guard let result = corrected() else { error = "Keep the corners in order around a rectangular page."; return }
                accept(result); dismiss()
            }.buttonStyle(.borderedProminent).padding(.bottom)
        }
        .background(AmbientBackground()).navigationTitle("Crop and straighten")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    private func reset() { corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]; error = nil }
    private func detect() {
        guard let cgImage = image.cgImage else { return }
        let request = VNDetectRectanglesRequest(); request.maximumObservations = 1; request.minimumConfidence = 0.6
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            guard let page = request.results?.first else { error = "No page boundary found. Adjust the corners manually."; return }
            corners = [page.topLeft, page.topRight, page.bottomRight, page.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func corrected() -> UIImage? {
        // Refuse crossing or degenerate quadrilaterals rather than corrupting the image.
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
            guard (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 0.005 else { return nil }
        }
        guard let input = CIImage(image: image) else { return nil }
        let p = corners.map { CGPoint(x: $0.x * input.extent.width, y: (1 - $0.y) * input.extent.height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input; filter.topLeft = p[0]; filter.topRight = p[1]; filter.bottomRight = p[2]; filter.bottomLeft = p[3]
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct CropHandle: View {
    @Binding var point: CGPoint
    let size: CGSize
    let label: String
    private var value: String { "Horizontal \(Int(point.x * 100)) percent, vertical \(Int(point.y * 100)) percent" }
    var body: some View {
        Circle().fill(Palette.brand).frame(width: 44, height: 44)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .position(x: point.x * size.width, y: point.y * size.height)
            .gesture(DragGesture(coordinateSpace: .named("crop")).onChanged { gesture in
                point = CGPoint(x: min(1, max(0, gesture.location.x / size.width)), y: min(1, max(0, gesture.location.y / size.height)))
            })
            .accessibilityLabel(label).accessibilityValue(value)
            .accessibilityAction(named: "Move left") { move(-0.02, 0) }
            .accessibilityAction(named: "Move right") { move(0.02, 0) }
            .accessibilityAction(named: "Move up") { move(0, -0.02) }
            .accessibilityAction(named: "Move down") { move(0, 0.02) }
    }
    private func move(_ dx: CGFloat, _ dy: CGFloat) {
        point = CGPoint(x: min(1, max(0, point.x + dx)), y: min(1, max(0, point.y + dy)))
    }
}

extension UIImage {
    func normalizedScoreJPEG(maxDimension: CGFloat = 3000) -> (image: UIImage, data: Data)? {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixels.width > 0, pixels.height > 0, pixels.width * pixels.height <= 100_000_000 else { return nil }
        let ratio = min(1, maxDimension / max(pixels.width, pixels.height))
        let target = CGSize(width: max(1, (pixels.width * ratio).rounded()), height: max(1, (pixels.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: target)); draw(in: CGRect(origin: .zero, size: target))
        }
        guard let bytes = normalized.jpegData(compressionQuality: 0.9) else { return nil }
        return (normalized, bytes)
    }
    func rotatedClockwise() -> UIImage {
        let target = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            context.cgContext.translateBy(x: target.width, y: 0); context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#endif
