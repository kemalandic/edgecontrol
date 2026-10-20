import CoreGraphics

/// How the Cameras widget lays out a grid of cameras.
///
/// The columns are the ones that give each camera the biggest 16:9 picture.
/// With "Fill the Tile" off, cells keep that shape and the grid is centered,
/// so every picture is whole. With it on, the cells stretch to the widget's
/// edges, a short last row widens to use the whole row, and each camera is
/// cropped to its cell.
enum CameraGrid {
    /// At least half the widget across is on the dashboard. `dashboard` is
    /// the dashboard's bounds in the widget's own coordinates, which is what
    /// `GeometryProxy.bounds(of:)` returns. Comparing that with the widget's
    /// frame in the dashboard's coordinates, as this once did, counted every
    /// widget right of about the middle as off screen, and its cameras
    /// stopped. Outside a dashboard (nil), it's on screen.
    static func isOnScreen(size: CGSize, dashboard: CGRect?) -> Bool {
        guard let dashboard, size.width > 0 else { return true }
        return CGRect(origin: .zero, size: size).intersection(dashboard).width >= size.width / 2
    }

    struct Arrangement: Equatable {
        let columns: Int
        let rows: Int
        let cellSize: CGSize
        /// Cameras per page; the rest go on further pages.
        let perPage: Int
    }

    static let aspect: CGFloat = 16 / 9
    /// Below this a camera is too small to make out; extra cameras page instead.
    static let minimumCell = CGSize(width: 150, height: 84)

    static func arrange(count: Int, in size: CGSize, spacing: CGFloat) -> Arrangement {
        let count = max(1, count)
        for perPage in stride(from: count, to: 1, by: -1) {
            let best = bestFit(count: perPage, in: size, spacing: spacing)
            if best.cellSize.width >= minimumCell.width, best.cellSize.height >= minimumCell.height {
                return best
            }
        }
        return bestFit(count: 1, in: size, spacing: spacing)
    }

    /// Where each of a page's `count` cameras goes, in reading order.
    static func frames(
        count: Int, arrangement: Arrangement, in size: CGSize, spacing: CGFloat, fill: Bool
    ) -> [CGRect] {
        let count = min(count, arrangement.perPage)
        guard count > 0 else { return [] }
        let columns = arrangement.columns
        let rows = (count + columns - 1) / columns

        guard fill else {
            let cell = arrangement.cellSize
            let width = CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing
            let height = CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing
            let origin = CGPoint(x: ((size.width - width) / 2).rounded(), y: ((size.height - height) / 2).rounded())
            return (0..<count).map { index in
                CGRect(
                    x: origin.x + CGFloat(index % columns) * (cell.width + spacing),
                    y: origin.y + CGFloat(index / columns) * (cell.height + spacing),
                    width: cell.width, height: cell.height)
            }
        }

        let height = ((size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)).rounded(.down)
        return (0..<count).map { index in
            let row = index / columns
            let inRow = row == rows - 1 ? count - row * columns : columns
            let width = ((size.width - spacing * CGFloat(inRow - 1)) / CGFloat(inRow)).rounded(.down)
            return CGRect(
                x: CGFloat(index % columns) * (width + spacing), y: CGFloat(row) * (height + spacing),
                width: width, height: height)
        }
    }

    /// The columns × rows that give `count` cameras the biggest cells.
    private static func bestFit(count: Int, in size: CGSize, spacing: CGFloat) -> Arrangement {
        var best: (arrangement: Arrangement, score: CGFloat)?
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let width = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            guard width > 0, height > 0 else { continue }
            let cellWidth = min(width, height * aspect).rounded(.down)
            // On a tie, fewer empty cells.
            let score = cellWidth - CGFloat(columns * rows - count) * 0.5
            if best == nil || score > best!.score {
                let cell = CGSize(width: cellWidth, height: (cellWidth / aspect).rounded(.down))
                best = (Arrangement(columns: columns, rows: rows, cellSize: cell, perPage: count), score)
            }
        }
        return best?.arrangement
            ?? Arrangement(columns: 1, rows: 1, cellSize: CGSize(width: size.width, height: size.height), perPage: 1)
    }
}
