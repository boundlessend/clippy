import SwiftUI

// речевой баллон над скрепышем: скруглённый прямоугольник с хвостиком вниз
struct SpeechBubbleView: View {
    let text: String
    private let tail: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10 + tail)
            .background(
                BubbleShape(tail: tail)
                    .fill(Color(white: 0.98))
                    .overlay(BubbleShape(tail: tail).stroke(.black.opacity(0.25), lineWidth: 1))
            )
            .padding(6)                       // запас под обводку внутри панели
    }
}

struct BubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - tail)
        var p = Path(roundedRect: body, cornerRadius: 12)
        let cx = rect.midX
        p.move(to: CGPoint(x: cx - 8, y: body.maxY))
        p.addLine(to: CGPoint(x: cx, y: rect.maxY))
        p.addLine(to: CGPoint(x: cx + 8, y: body.maxY))
        p.closeSubpath()
        return p
    }
}
