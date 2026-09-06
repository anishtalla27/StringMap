import SwiftUI

/// Bundled policies remain readable offline; public links point to the same text.
struct LegalDocumentView: View {
    let name: String
    let title: String
    let publicURL: URL?
    private var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["This document could not be loaded. Contact stringmap.support@gmail.com."] }
        return text.components(separatedBy: "\n\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let publicURL { Link("Read on the web", destination: publicURL) }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("#") {
                        Text(paragraph.trimmingCharacters(in: CharacterSet(charactersIn: "# \n")))
                            .font(.headline).accessibilityAddTraits(.isHeader)
                    } else {
                        Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                            .textSelection(.enabled)
                    }
                }
                if name == "support" { Link("Email support", destination: URL(string: "mailto:stringmap.support@gmail.com")!) }
            }.padding().frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle(title).background(AmbientBackground())
    }
}
