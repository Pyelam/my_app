import Foundation
import Testing
@testable import TwigCore

struct TreeAndDateTests {
    @Test func collapsedBranchDoesNotReappearAsAnOrphan() {
        let root = UUID(), child = UUID(), grandchild = UUID(), sibling = UUID()
        let nodes = [TreeNode(id: root, parentID: nil, collapsed: true),
                     TreeNode(id: child, parentID: root), TreeNode(id: grandchild, parentID: child),
                     TreeNode(id: sibling, parentID: nil)]
        #expect(TreeTopology.flatten(nodes).map(\.id) == [root, sibling])
    }

    @Test func missingParentStaysVisible() {
        let id = UUID()
        #expect(TreeTopology.flatten([TreeNode(id: id, parentID: UUID())]) == [TreePlacement(id: id, depth: 0)])
    }

    @Test func cycleTraversalTerminatesAndKeepsBothNotesVisible() {
        let a = UUID(), b = UUID()
        let nodes = [TreeNode(id: a, parentID: b), TreeNode(id: b, parentID: a)]
        #expect(Set(TreeTopology.flatten(nodes).map(\.id)) == Set([a, b]))
        #expect(TreeTopology.descendants(of: a, nodes: nodes) == Set([a, b]))
    }

    @Test func deepTreeUsesIterativeTraversal() {
        let ids = (0..<5_000).map { _ in UUID() }
        let nodes = ids.enumerated().map { index, id in TreeNode(id: id, parentID: index == 0 ? nil : ids[index - 1]) }
        let rows = TreeTopology.flatten(nodes)
        #expect(rows.count == 5_000)
        #expect(rows.last?.depth == 4_999)
    }

    @Test func siblingOrderIsPreserved() {
        let root = UUID(), first = UUID(), second = UUID()
        let nodes = [TreeNode(id: root, parentID: nil), TreeNode(id: first, parentID: root), TreeNode(id: second, parentID: root)]
        #expect(TreeTopology.flatten(nodes).map(\.id) == [root, first, second])
    }

    @Test func calendarDayDoesNotShiftBetweenTimeZones() throws {
        for zone in ["Asia/Seoul", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let timeZone = try #require(TimeZone(identifier: zone))
            let date = try #require(CalendarDay.date("2026-09-16", timeZone: timeZone))
            #expect(CalendarDay.string(date, timeZone: timeZone) == "2026-09-16")
        }
    }

    @Test func invalidDateIsRejected() {
        #expect(CalendarDay.date("2026-02-30") == nil)
        #expect(CalendarDay.date("2026-2-1") == nil)
        #expect(CalendarDay.date("invalid") == nil)
        #expect(CalendarDay.date("2024-02-29") != nil)
    }

    @Test func tagsAreNormalizedAndDeduplicated() {
        #expect(NoteDraft.normalizedTags("#Swift swift, #앱\n콘텐츠") == ["swift", "앱", "콘텐츠"])
        #expect(NoteDraft.normalizedTags(" # , ") == [])
    }

    @Test func titleIsOptional() {
        #expect(NoteDraft(content: "본문만 있는 메모").label == "본문만 있는 메모")
        #expect(NoteDraft(title: "제목", content: "본문").label == "제목")
        #expect(NoteDraft(content: " \n").label == "새 영감")
    }
}
