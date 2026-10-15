import CoreGraphics

public struct GridMetrics: Equatable, Sendable {
    public var thumbnailHeight: CGFloat
    public var titleHeight: CGFloat
    /// Space between a cell's edge and its thumbnail.
    public var cellPadding: CGFloat
    public var spacing: CGFloat
    /// Space between the panel edge and the cells.
    public var inset: CGFloat

    public init(thumbnailHeight: CGFloat = 130, titleHeight: CGFloat = 20, cellPadding: CGFloat = 8, spacing: CGFloat = 8, inset: CGFloat = 16) {
        self.thumbnailHeight = thumbnailHeight
        self.titleHeight = titleHeight
        self.cellPadding = cellPadding
        self.spacing = spacing
        self.inset = inset
    }

    public var minAspect: CGFloat { 0.75 }
    public var maxAspect: CGFloat { 2.0 }
}

public enum GridDirection: Sendable {
    case left, right, up, down
}

/// Cell frames for the overlay, in a flipped (top-left origin) coordinate space.
public struct GridLayout: Equatable, Sendable {
    public let cellFrames: [CGRect]
    public let rows: [[Int]]
    /// Size of all content. The panel may be shorter than this and scroll.
    public let contentSize: CGSize
    /// Size the panel should take: content clamped to the max size.
    public let viewportSize: CGSize

    /// - Parameters:
    ///   - aspectRatios: width / height of each window, in display order.
    ///   - maxSize: the largest the panel may be (about 90% of the screen).
    public static func compute(aspectRatios: [CGFloat], maxSize: CGSize, metrics: GridMetrics) -> GridLayout {
        let available = max(maxSize.width - 2 * metrics.inset, 1)
        let cellHeight = metrics.thumbnailHeight + metrics.titleHeight + 2 * metrics.cellPadding
        let maxCellWidth = available

        let widths: [CGFloat] = aspectRatios.map { ratio in
            let safe = ratio.isFinite && ratio > 0 ? ratio : 1
            let clamped = min(max(safe, metrics.minAspect), metrics.maxAspect)
            return min(metrics.thumbnailHeight * clamped + 2 * metrics.cellPadding, maxCellWidth)
        }

        // Greedy row filling.
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : currentWidth + metrics.spacing + width
            if needed > available && !current.isEmpty {
                rows.append(current)
                current = [index]
                currentWidth = width
            } else {
                current.append(index)
                currentWidth = needed
            }
        }
        if !current.isEmpty { rows.append(current) }

        func rowWidth(_ row: [Int]) -> CGFloat {
            row.map { widths[$0] }.reduce(0, +) + metrics.spacing * CGFloat(max(row.count - 1, 0))
        }
        let contentWidth = rows.map(rowWidth).max() ?? 0

        var frames = Array(repeating: CGRect.zero, count: widths.count)
        for (rowIndex, row) in rows.enumerated() {
            var x = metrics.inset + (contentWidth - rowWidth(row)) / 2
            let y = metrics.inset + CGFloat(rowIndex) * (cellHeight + metrics.spacing)
            for index in row {
                frames[index] = CGRect(x: x, y: y, width: widths[index], height: cellHeight)
                x += widths[index] + metrics.spacing
            }
        }

        let rowCount = CGFloat(rows.count)
        let contentSize = CGSize(
            width: contentWidth + 2 * metrics.inset,
            height: rows.isEmpty ? 2 * metrics.inset : rowCount * cellHeight + (rowCount - 1) * metrics.spacing + 2 * metrics.inset
        )
        let viewport = CGSize(width: min(contentSize.width, maxSize.width), height: min(contentSize.height, maxSize.height))
        return GridLayout(cellFrames: frames, rows: rows, contentSize: contentSize, viewportSize: viewport)
    }

    public func index(at point: CGPoint) -> Int? {
        cellFrames.firstIndex { $0.contains(point) }
    }

    /// Left/right step through the whole list with wrap-around. Up/down jump to the
    /// cell in the adjacent row (wrapping) whose centre is horizontally closest.
    public func neighbor(of index: Int, _ direction: GridDirection) -> Int {
        let count = cellFrames.count
        guard count > 0, index >= 0, index < count else { return index }
        switch direction {
        case .left: return (index - 1 + count) % count
        case .right: return (index + 1) % count
        case .up, .down:
            guard rows.count > 1, let rowIndex = rows.firstIndex(where: { $0.contains(index) }) else { return index }
            let step = direction == .down ? 1 : -1
            let target = rows[(rowIndex + step + rows.count) % rows.count]
            let midX = cellFrames[index].midX
            return target.min { abs(cellFrames[$0].midX - midX) < abs(cellFrames[$1].midX - midX) } ?? index
        }
    }
}
