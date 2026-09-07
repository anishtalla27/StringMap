import XCTest
import UIKit
@testable import StringMap

final class ScanImageTests: XCTestCase {
    func testCorrectionTimingPreservesFractionsAndRejectsInvalidInput() throws {
        XCTAssertEqual(try XCTUnwrap(ScoreTimingInput.parse("1/3")), 1.0 / 3, accuracy: 1e-15)
        XCTAssertEqual(ScoreTimingInput.parse("1,5"), 1.5)
        XCTAssertEqual(ScoreTimingInput.parse(ScoreTimingInput.format(5.0 / 3)), 5.0 / 3)
        for invalid in ["1/0", "-1", "NaN", "inf", "129", "1/2/3", "1/"] {
            XCTAssertNil(ScoreTimingInput.parse(invalid), invalid)
        }
    }

    @MainActor
    func testNormalizationUsesPixelLimitAndRemovesScaleAndOrientation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        }
        let normalized = try XCTUnwrap(original.normalizedScoreJPEG(maxDimension: 1500))
        XCTAssertEqual(normalized.image.cgImage?.width, 1500)
        XCTAssertEqual(normalized.image.cgImage?.height, 750)
        XCTAssertEqual(normalized.image.scale, 1); XCTAssertEqual(normalized.image.imageOrientation, .up)
        let rotated = normalized.image.rotatedClockwise()
        XCTAssertEqual(rotated.cgImage?.width, 750); XCTAssertEqual(rotated.cgImage?.height, 1500)
        XCTAssertNotNil(UIImage(data: normalized.data))
    }
}
