import SwiftUI

/// A teardrop that morphs into a capsule.
///
/// `morph` 0 draws a drop with a pointed tip; 1 draws a pill. Everything in
/// between is a continuous blend, which is what lets the drop fall in and then
/// stretch open into the amplitude meter in one unbroken motion.
///
/// The silhouette is four pieces: a flat top edge (zero-length for the drop,
/// so the sides meet at a point), a curve down each side into the widest point,
/// and a rounded bottom. Every parameter moves monotonically with `morph`, so
/// no stage of the animation grows a shoulder or a lobe.
struct TeardropShape: Shape {
    var morph: Double

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    /// Distance from a circle's quadrant point to its cubic control point.
    private static let circleControl = 0.5523

    func path(in rect: CGRect) -> Path {
        let t = min(max(morph, 0), 1)
        let half = rect.width / 2
        let height = rect.height
        let centerX = rect.midX
        let top = rect.minY
        let bottom = rect.maxY

        // Bottom corner radius: the full half-width for the drop (a round
        // bottom), half the height once it is a pill.
        let bottomRadius = min(half, height / 2)
        // Half-width of the flat top edge — zero for the drop's point. It opens
        // up late (squared) so the tip stays a tip until the body is wide,
        // instead of creasing into a flat top halfway through the morph.
        let apex = (half - bottomRadius) * t * t
        // The widest point sits low on a drop and halfway up a pill, and never
        // below where the bottom corner starts.
        let waistY = min(height * (0.62 - 0.12 * t), height - bottomRadius)

        // Tip controls: tucked in and dropped below the apex for a sharp point,
        // flung outward and level with it for a rounded corner.
        let shoulderX = apex + (half - apex) * (0.35 + 0.45 * t)
        let shoulderY = pow(1 - t, 1.6) * height * 0.22
        let waistControlY = waistY - Self.circleControl * min(waistY, half)

        var path = Path()
        path.move(to: CGPoint(x: centerX - apex, y: top))
        if apex > 0 {
            path.addLine(to: CGPoint(x: centerX + apex, y: top))
        }

        path.addCurve(
            to: CGPoint(x: centerX + half, y: top + waistY),
            control1: CGPoint(x: centerX + shoulderX, y: top + shoulderY),
            control2: CGPoint(x: centerX + half, y: top + waistControlY))

        path.addLine(to: CGPoint(x: centerX + half, y: bottom - bottomRadius))
        path.addArc(
            center: CGPoint(x: centerX + half - bottomRadius, y: bottom - bottomRadius),
            radius: bottomRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: centerX - half + bottomRadius, y: bottom))
        path.addArc(
            center: CGPoint(x: centerX - half + bottomRadius, y: bottom - bottomRadius),
            radius: bottomRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        path.addLine(to: CGPoint(x: centerX - half, y: top + waistY))
        path.addCurve(
            to: CGPoint(x: centerX - apex, y: top),
            control1: CGPoint(x: centerX - half, y: top + waistControlY),
            control2: CGPoint(x: centerX - shoulderX, y: top + shoulderY))

        path.closeSubpath()
        return path
    }
}
