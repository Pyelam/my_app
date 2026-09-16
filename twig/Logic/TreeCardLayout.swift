import Foundation

// Automatic outline geometry; no saved canvas coordinates or drag placement.
struct TreeCardLayout {
    struct Card: Identifiable {
        let id: UUID
        let depth: Int
        let x: Double
        let y: Double
    }
    struct Connection {
        let parentID: UUID
        let childID: UUID
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
    }

    let cards: [Card]
    let connections: [Connection]
    let width: Double
    let height: Double

    static func make(nodes: [TreeNode], cardWidth: Double = 176, cardHeight: Double = 72,
                     indent: Double = 36, gap: Double = 14, padding: Double = 24) -> TreeCardLayout {
        let placements = TreeTopology.flatten(nodes)
        let cards = placements.enumerated().map { index, placement in
            Card(id: placement.id, depth: placement.depth,
                 x: padding + Double(placement.depth) * indent,
                 y: padding + Double(index) * (cardHeight + gap))
        }
        let frames = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let parents = Dictionary(nodes.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        let connections = cards.compactMap { child -> Connection? in
            guard let parentID = parents[child.id] ?? nil, let parent = frames[parentID],
                  parent.y < child.y, parent.depth + 1 == child.depth else { return nil }
            return Connection(parentID: parentID, childID: child.id,
                              startX: parent.x + indent / 2, startY: parent.y + cardHeight,
                              endX: child.x, endY: child.y + cardHeight / 2)
        }
        return TreeCardLayout(cards: cards, connections: connections,
            width: (cards.map(\.x).max() ?? padding) + cardWidth + 48 + padding,
            height: (cards.last?.y ?? padding) + cardHeight + padding)
    }
}
