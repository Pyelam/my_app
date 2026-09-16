import Foundation

struct TreeNode {
    let id: UUID
    let parentID: UUID?
    var collapsed = false
}

struct TreePlacement: Equatable {
    let id: UUID
    let depth: Int
}

enum TreeTopology {
    // Input order is sibling order. Iterative traversal supports deeply nested notes.
    static func flatten(_ nodes: [TreeNode]) -> [TreePlacement] {
        let ids = Set(nodes.map(\.id))
        let children = Dictionary(grouping: nodes.filter { $0.parentID != nil }, by: { $0.parentID! })
        let roots = nodes.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        var result: [TreePlacement] = []
        var visited = Set<UUID>()
        func visit(_ root: TreeNode) {
            var stack: [(TreeNode, Int, Bool)] = [(root, 0, true)]
            while let (node, depth, visible) = stack.popLast() {
                guard visited.insert(node.id).inserted else { continue }
                if visible { result.append(TreePlacement(id: node.id, depth: depth)) }
                for child in (children[node.id] ?? []).reversed() {
                    stack.append((child, depth + 1, visible && !node.collapsed))
                }
            }
        }
        roots.forEach(visit)
        // Cycles from concurrent reparenting remain visible and can be repaired by moving a node.
        for node in nodes where !visited.contains(node.id) { visit(node) }
        return result
    }

    static func descendants(of id: UUID, nodes: [TreeNode]) -> Set<UUID> {
        let children = Dictionary(grouping: nodes.filter { $0.parentID != nil }, by: { $0.parentID! })
        var visited: Set<UUID> = [id]
        var pending = [id]
        while let parent = pending.popLast() {
            for child in children[parent] ?? [] where visited.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return visited
    }
}
