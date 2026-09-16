import Foundation
import Testing
@testable import TwigCore

struct TreeCardLayoutTests {
    @Test func connectionsStayInsideTheirOwnTree() {
        let firstRoot = UUID(), child = UUID(), otherRoot = UUID()
        let layout = TreeCardLayout.make(nodes: [TreeNode(id: firstRoot, parentID: nil),
                                               TreeNode(id: child, parentID: firstRoot),
                                               TreeNode(id: otherRoot, parentID: nil)])
        #expect(layout.cards.count == 3)
        #expect(layout.connections.count == 1)
        #expect(layout.connections.first?.parentID == firstRoot)
        #expect(layout.connections.first?.childID == child)
    }

    @Test func collapsedBranchHasNoDanglingConnections() {
        let root = UUID(), child = UUID(), grandchild = UUID()
        let layout = TreeCardLayout.make(nodes: [TreeNode(id: root, parentID: nil, collapsed: true),
                                               TreeNode(id: child, parentID: root),
                                               TreeNode(id: grandchild, parentID: child)])
        #expect(layout.cards.map(\.id) == [root])
        #expect(layout.connections.isEmpty)
    }

    @Test func largeTypeDoesNotOverlapCardsOrClipAddButtons() {
        let root = UUID(), child = UUID(), sibling = UUID()
        let width = 320.0, height = 140.0
        let layout = TreeCardLayout.make(nodes: [TreeNode(id: root, parentID: nil),
                                               TreeNode(id: child, parentID: root),
                                               TreeNode(id: sibling, parentID: root)],
                                         cardWidth: width, cardHeight: height)
        for pair in zip(layout.cards, layout.cards.dropFirst()) {
            #expect(pair.0.y + height < pair.1.y)
        }
        for card in layout.cards {
            #expect(card.x + width + 44 <= layout.width)
            #expect(card.y + height <= layout.height)
        }
        for edge in layout.connections {
            let parent = layout.cards.first { $0.id == edge.parentID }
            let child = layout.cards.first { $0.id == edge.childID }
            #expect(edge.startY == (parent?.y ?? 0) + height)
            #expect(edge.endX == child?.x)
            #expect(edge.startY < edge.endY)
        }
    }

    @Test func brokenReferencesDoNotDrawBackwardOrInventedEdges() {
        let a = UUID(), b = UUID(), orphan = UUID()
        let layout = TreeCardLayout.make(nodes: [TreeNode(id: a, parentID: b),
                                               TreeNode(id: b, parentID: a),
                                               TreeNode(id: orphan, parentID: UUID())])
        #expect(Set(layout.cards.map(\.id)) == Set([a, b, orphan]))
        #expect(!layout.connections.contains { $0.childID == orphan })
        #expect(layout.connections.allSatisfy { $0.startY < $0.endY && $0.startX < $0.endX })
    }
}
