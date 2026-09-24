import Foundation

enum NaturalCommandWindowMeaning {
    static func describe(_ id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: "Place the current window in the left half of the screen."
        case .rightHalf: "Place the current window in the right half of the screen."
        case .topHalf: "Place the current window in the upper half of the screen."
        case .bottomHalf: "Place the current window in the lower half of the screen."
        case .topLeftQuarter: "Place the current window in the upper-left quarter."
        case .topRightQuarter: "Place the current window in the upper-right quarter."
        case .bottomLeftQuarter: "Place the current window in the lower-left quarter."
        case .bottomRightQuarter: "Place the current window in the lower-right quarter."
        case .firstThreeFourths: "Place the current window in the left three quarters of the screen."
        case .lastThreeFourths: "Place the current window in the right three quarters of the screen."
        case .firstThird: "Place the current window in the leftmost third of the screen."
        case .centerThird: "Place the current window in the center third of the screen."
        case .lastThird: "Place the current window in the rightmost third of the screen."
        case .firstTwoThirds: "Place the current window in the left two thirds of the screen."
        case .lastTwoThirds: "Place the current window in the right two thirds of the screen."
        case .maximize: "Fill the available screen with the current window."
        case .almostMaximize: "Make the current window nearly fill the screen, leaving a margin."
        case .reasonableSize: "Resize the current window to a comfortable size."
        case .maximizeHeight: "Fill the screen height while keeping the window width."
        case .maximizeWidth: "Fill the screen width while keeping the window height."
        case .center: "Move the current window to the center without resizing it."
        case .centerHalf: "Place the current window in the centered half of the screen."
        case .centerTwoThirds: "Place the current window in the centered two thirds of the screen."
        case .makeLarger: "Increase the size of the current window."
        case .makeSmaller: "Decrease the size of the current window."
        case .restore: "Restore the current window to its previous size and position."
        case .moveLeft: "Move the current window left without resizing it."
        case .moveRight: "Move the current window right without resizing it."
        case .moveUp: "Move the current window up without resizing it."
        case .moveDown: "Move the current window down without resizing it."
        case .nextDisplay: "Move the current window to the next display."
        case .previousDisplay: "Move the current window to the previous display."
        case .toggleFullscreen: "Enter or exit fullscreen for the current window."
        case .previousSpace: "Switch to the previous desktop Space."
        case .nextSpace: "Switch to the next desktop Space."
        }
    }
}
