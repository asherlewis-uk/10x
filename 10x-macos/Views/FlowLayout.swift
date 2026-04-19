import SwiftUI

/// A layout that arranges views in a wrapping horizontal flow (like flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var rows: [[Int]] = [[]]  // indices per row
        var rowWidths: [CGFloat] = [0]
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowHeights: [CGFloat] = []
        var totalWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                rowHeights.append(rowHeight)
                totalWidth = max(totalWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                rows.append([])
                rowWidths.append(0)
            }
            positions.append(CGPoint(x: x, y: y))
            rows[rows.count - 1].append(index)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            rowWidths[rowWidths.count - 1] = x - spacing
        }
        rowHeights.append(rowHeight)
        totalWidth = max(totalWidth, x - spacing)

        // Apply horizontal centering if needed
        if alignment == .center {
            let containerWidth = min(maxWidth, totalWidth)
            for (rowIndex, indices) in rows.enumerated() {
                let rowWidth = rowWidths[rowIndex]
                let offset = max(0, (containerWidth - rowWidth) / 2)
                for i in indices {
                    positions[i].x += offset
                }
            }
        }

        return ArrangeResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: y + rowHeight)
        )
    }
}
