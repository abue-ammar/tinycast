import SwiftUI

/// The camera's action row, in the same button language a dialog's footer speaks.
struct CameraButton: View {
    /// Secondary also reads as "off": the mirror toggle dims rather than growing a second style.
    enum Emphasis {
        case primary
        case secondary
    }

    let title: String
    var keyCap: String?
    var emphasis: Emphasis = .primary
    let onActivate: () -> Void

    var body: some View {
        Button(title, action: onActivate)
            .buttonStyle(.modalAction(role, fillsWidth: false))
            .tooltip(keyCap: keyCap)
    }

    private var role: ModalActionButtonStyle.Role {
        emphasis == .primary ? .primary : .cancel
    }
}
