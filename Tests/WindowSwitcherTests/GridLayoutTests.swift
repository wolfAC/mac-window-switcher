import CoreGraphics
import Testing
@testable import SwitcherCore

@Suite struct GridLayoutTests {
    let metrics = GridMetrics(thumbnailHeight: 100, titleHeight: 20, cellPadding: 10, spacing: 10, inset: 20)
    // Cell height = 100 + 20 + 2*10 = 140.

    @Test func emptyList() {
        let layout = GridLayout.compute(aspectRatios: [], maxSize: CGSize(width: 1000, height: 800), metrics: metrics)
        #expect(layout.rows.isEmpty)
        #expect(layout.cellFrames.isEmpty)
        #expect(layout.contentSize == CGSize(width: 40, height: 40))
    }

    @Test func singleRowSizesFromAspectRatio() {
        // 1.5 → 150 + 20 padding = 170 wide.
        let layout = GridLayout.compute(aspectRatios: [1.5, 1.5], maxSize: CGSize(width: 1000, height: 800), metrics: metrics)
        #expect(layout.rows == [[0, 1]])
        #expect(layout.cellFrames[0] == CGRect(x: 20, y: 20, width: 170, height: 140))
        #expect(layout.cellFrames[1] == CGRect(x: 200, y: 20, width: 170, height: 140))
        #expect(layout.contentSize == CGSize(width: 390, height: 180))
        #expect(layout.viewportSize == layout.contentSize)
    }

    @Test func aspectRatioIsClamped() {
        // 10:1 clamps to 2:1 → 220; 0.1 clamps to 0.75 → 95; NaN → 1 → 120.
        let layout = GridLayout.compute(aspectRatios: [10, 0.1, .nan], maxSize: CGSize(width: 2000, height: 800), metrics: metrics)
        #expect(layout.cellFrames.map(\.width) == [220, 95, 120])
    }

    @Test func wrapsIntoCentredRows() {
        // Available width = 500 - 40 = 460. Cells are 120 wide: 3 per row = 380, 4 = 510.
        let layout = GridLayout.compute(aspectRatios: Array(repeating: 1, count: 7), maxSize: CGSize(width: 500, height: 2000), metrics: metrics)
        #expect(layout.rows == [[0, 1, 2], [3, 4, 5], [6]])
        #expect(layout.contentSize.width == 420)
        // The last row's single cell is centred.
        #expect(layout.cellFrames[6].midX == layout.contentSize.width / 2)
        #expect(layout.cellFrames[3].minY == 170) // inset + row + gap
        #expect(layout.contentSize.height == 480) // 3 rows × 140 + 2 gaps × 10 + 2 × 20 inset
    }

    @Test func tallListScrolls() {
        let layout = GridLayout.compute(aspectRatios: Array(repeating: 1, count: 30), maxSize: CGSize(width: 500, height: 400), metrics: metrics)
        #expect(layout.contentSize.height > 400)
        #expect(layout.viewportSize.height == 400)
    }

    @Test func navigation() {
        let layout = GridLayout.compute(aspectRatios: Array(repeating: 1, count: 7), maxSize: CGSize(width: 500, height: 2000), metrics: metrics)
        #expect(layout.neighbor(of: 0, .left) == 6)
        #expect(layout.neighbor(of: 6, .right) == 0)
        #expect(layout.neighbor(of: 1, .down) == 4)
        #expect(layout.neighbor(of: 4, .down) == 6)
        #expect(layout.neighbor(of: 6, .down) == 1)
        #expect(layout.neighbor(of: 0, .up) == 6)
    }

    @Test func hitTesting() {
        let layout = GridLayout.compute(aspectRatios: [1, 1], maxSize: CGSize(width: 1000, height: 800), metrics: metrics)
        #expect(layout.index(at: CGPoint(x: 30, y: 30)) == 0)
        #expect(layout.index(at: CGPoint(x: 5, y: 5)) == nil)
    }
}
