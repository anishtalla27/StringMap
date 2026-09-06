// Research-only image text observations. No music reference or note prediction is read.
import Foundation
import Vision
import ImageIO

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.minimumTextHeight = 0.005
try VNImageRequestHandler(url: url, options: [:]).perform([request])
let rows = (request.results ?? []).map { observation -> [String: Any] in
    let box = observation.boundingBox
    return ["box": [box.minX, box.minY, box.width, box.height],
            "candidates": observation.topCandidates(3).map { ["text": $0.string, "confidence": $0.confidence] }]
}
let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
