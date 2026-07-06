import SwiftUI

// речевой баллон у иконки в доке: скруглённый прямоугольник с хвостиком в сторону дока
struct SpeechBubbleView: View {
    let text: String
    let dock: DockOrientation
    private let tail: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(edgePadding, tail)                 // запас под хвостик со стороны дока
            .background(
                BubbleShape(tail: tail, dock: dock)
                    .fill(Color(white: 0.98))
                    .overlay(BubbleShape(tail: tail, dock: dock).stroke(.black.opacity(0.25), lineWidth: 1))
            )
            .padding(6)                                 // запас под обводку внутри панели
            .fixedSize()                                // плотный размер для NSHostingView
    }

    // хвостик смотрит в сторону дока: низ дока -> вниз, слева -> влево, справа -> вправо
    private var edgePadding: Edge.Set {
        switch dock {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

// скруглённый прямоугольник с треугольным хвостиком на стороне дока
struct BubbleShape: Shape {
    let tail: CGFloat
    let dock: DockOrientation

    func path(in rect: CGRect) -> Path {
        // тело - прямоугольник, отступивший от края хвостика на tail
        let body: CGRect
        switch dock {
        case .bottom: body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        case .left:   body = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        case .right:  body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height)
        }
        var p = Path(roundedRect: body, cornerRadius: 12)
        switch dock {
        case .bottom:
            let cx = body.midX
            p.move(to: CGPoint(x: cx - 8, y: body.maxY))
            p.addLine(to: CGPoint(x: cx, y: rect.maxY))
            p.addLine(to: CGPoint(x: cx + 8, y: body.maxY))
        case .left:
            let cy = body.midY
            p.move(to: CGPoint(x: body.minX, y: cy - 8))
            p.addLine(to: CGPoint(x: rect.minX, y: cy))
            p.addLine(to: CGPoint(x: body.minX, y: cy + 8))
        case .right:
            let cy = body.midY
            p.move(to: CGPoint(x: body.maxX, y: cy - 8))
            p.addLine(to: CGPoint(x: rect.maxX, y: cy))
            p.addLine(to: CGPoint(x: body.maxX, y: cy + 8))
        }
        p.closeSubpath()
        return p
    }
}
