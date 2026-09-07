import SwiftUI

struct SourceImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    var body: some View {
        NavigationStack {
            ZoomablePage(image: UIImage(data: data))
                .navigationTitle("Source page")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ZoomablePage: UIViewRepresentable {
    let image: UIImage?
    func makeUIView(context: Context) -> PageScrollView { PageScrollView(image: image) }
    func updateUIView(_ view: PageScrollView, context: Context) {}
}

private final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    private let page: UIImageView
    private var lastSize = CGSize.zero
    init(image: UIImage?) {
        page = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self; maximumZoomScale = 5; minimumZoomScale = 0.05
        backgroundColor = .systemBackground
        page.frame = CGRect(origin: .zero, size: image?.size ?? CGSize(width: 1, height: 1))
        addSubview(page); contentSize = page.bounds.size
        isAccessibilityElement = true; accessibilityLabel = "Original sheet music. Pinch to zoom and drag to inspect the notes."
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(zoomIn)), UIAccessibilityCustomAction(name: "Zoom out", target: self, selector: #selector(zoomOut))]
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize, bounds.width > 0, bounds.height > 0 {
            lastSize = bounds.size
            let fit = min(bounds.width / page.bounds.width, bounds.height / page.bounds.height)
            minimumZoomScale = fit; maximumZoomScale = max(5, fit * 5)
            setZoomScale(fit, animated: false)
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { page }
    @objc private func zoomIn() -> Bool { setZoomScale(min(maximumZoomScale, zoomScale * 1.5), animated: true); return true }
    @objc private func zoomOut() -> Bool { setZoomScale(max(minimumZoomScale, zoomScale / 1.5), animated: true); return true }
}
