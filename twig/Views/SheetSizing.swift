import SwiftUI

extension View {
    @ViewBuilder
    func editorSheetSize(minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: 360, minHeight: minHeight)
        #else
        self
        #endif
    }
}
