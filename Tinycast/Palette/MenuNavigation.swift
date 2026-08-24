import Carbon.HIToolbox
import Foundation

enum MenuNavigation {
    /// Keys a frozen search field must still pass through to menu navigation.
    static let keyCodes: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
        kVK_ANSI_J, kVK_ANSI_K
    ]

    static func handles(_ keyCode: Int) -> Bool {
        keyCodes.contains(keyCode)
    }
}
