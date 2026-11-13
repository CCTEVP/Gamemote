import SwiftUI
import UIKit

/// The clay palette, shared by SwiftUI views and the RealityKit controller.
enum Clay {
    static let table = UIColor(hex: 0xF4DFC0)
    static let homeBackground = UIColor(hex: 0xE8DDCF)
    static let ink = UIColor(hex: 0x4A3F55)
    static let body = UIColor(hex: 0xA89A8C)
    static let teal = UIColor(hex: 0x7CBDB2)
    static let tealDark = UIColor(hex: 0x5B9E95)
    static let orange = UIColor(hex: 0xF58E5A)
    static let yellow = UIColor(hex: 0xF2C94C)
    static let coral = UIColor(hex: 0xE8746B)
    static let red = UIColor(hex: 0xE02A22)
    static let disabled = UIColor(hex: 0xD8CBBE)
    static let mint = UIColor(hex: 0x9FDCC2)
    static let sky = UIColor(hex: 0xA8D3F5)
    static let grape = UIColor(hex: 0xC7B3F2)
    static let screen = UIColor(hex: 0x1B202B)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(clay: UIColor) { self.init(uiColor: clay) }
}

/// A rounded grape pill button (Connect, Back).
struct PillButtonStyle: ButtonStyle {
    var color = Color(clay: Clay.grape)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(clay: Clay.ink))
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.75 : 1)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
