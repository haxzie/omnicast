import AppKit
import SwiftUI

/// The frosted-glass surface everything in Omnicast sits on.
///
/// `NSVisualEffectView` is what Spotlight itself uses — it samples the desktop
/// behind the window, so the panel picks up the user's wallpaper and tint for
/// free. On macOS 26 the system's Liquid Glass material is layered on top.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}

extension View {
    /// Rounded frosted panel with the hairline highlight macOS puts on glass.
    func glassPanel(cornerRadius: CGFloat = 20, material: NSVisualEffectView.Material = .hudWindow)
        -> some View
    {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, material: material))
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return
            content
            .background {
                if #available(macOS 26.0, *) {
                    // Liquid Glass: refracts and reacts to what's behind the window.
                    shape.fill(.clear).glassEffect(.regular, in: shape)
                } else {
                    VisualEffectBackground(material: material)
                }
            }
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
    }
}

/// A card inside the main window — lighter than the panel glass.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(macOS 26.0, *) {
                    shape.fill(.clear).glassEffect(.regular.tint(.white.opacity(0.03)), in: shape)
                } else {
                    shape.fill(.white.opacity(0.06))
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 0.8))
    }
}
