import SwiftUI

/// Main workspace view — chat panel + preview panel.
struct BuilderView: View {
    var body: some View {
        HSplitView {
            ChatPanelView()
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 500)

            PreviewPanelView()
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }
}
