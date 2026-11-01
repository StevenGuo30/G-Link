import SwiftUI
import AppKit

enum CityArtwork {
    static let names = ["shenzhen", "shanghai", "new-york", "chicago"]
    // Decode once per process, not on each connection status refresh.
    static let images: [NSImage?] = names.map { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "docs/assets/cities") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct ConnectionBackdrop: View {
    let city: Int
    var connected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var base: Color { connected ? Palette.midnight : Palette.paper }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                base
                RadialGradient(colors: connected
                    ? [Color(red: 0.12, green: 0.34, blue: 0.58), Palette.midnight]
                    : [Palette.ice, Palette.paper],
                    center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: 620)
                if let artwork = CityArtwork.images[min(max(city, 0), 3)] {
                    Image(nsImage: artwork).resizable().interpolation(.high)
                        .scaledToFit().frame(width: geometry.size.width * 1.03)
                        .saturation(connected ? 0.8 : 0.65)
                        .opacity(connected ? 0.82 : 0.58)
                        .overlay {
                            CityWindowLights(city: city)
                                .mask(Image(nsImage: artwork).resizable().scaledToFit())
                                .opacity(connected ? 1 : 0)
                                .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: connected)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height * 0.76, alignment: .bottom)
                        .mask(LinearGradient(stops: [
                            .init(color: .white.opacity(0.3), location: 0),
                            .init(color: .white, location: 0.24),
                            .init(color: .white, location: 0.82),
                            .init(color: .white.opacity(0.15), location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                }
                RadialGradient(colors: [base.opacity(connected ? 0.7 : 0.76), base.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.32), startRadius: 55, endRadius: 290)
                LinearGradient(colors: [.clear, base.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }.clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct CityWindowLights: View {
    let city: Int
    private struct Window {
        let point: CGPoint
        let warmth: Bool
        let brightness: Double
        let width: CGFloat
    }
    // Normalized facade bounds in each supplied cutout, excluding spires and trees.
    // The image's alpha mask additionally keeps every light inside the architecture.
    private static let facades: [[CGRect]] = [
        [CGRect(x: 0.111, y: 0.66, width: 0.026, height: 0.23),
         CGRect(x: 0.236, y: 0.72, width: 0.025, height: 0.17),
         CGRect(x: 0.325, y: 0.55, width: 0.025, height: 0.29),
         CGRect(x: 0.352, y: 0.65, width: 0.027, height: 0.21),
         CGRect(x: 0.439, y: 0.66, width: 0.031, height: 0.20),
         CGRect(x: 0.489, y: 0.42, width: 0.033, height: 0.34),
         CGRect(x: 0.574, y: 0.40, width: 0.031, height: 0.35),
         CGRect(x: 0.533, y: 0.71, width: 0.033, height: 0.20),
         CGRect(x: 0.704, y: 0.23, width: 0.018, height: 0.65),
         CGRect(x: 0.727, y: 0.29, width: 0.016, height: 0.59),
         CGRect(x: 0.779, y: 0.57, width: 0.025, height: 0.26),
         CGRect(x: 0.859, y: 0.69, width: 0.029, height: 0.17),
         CGRect(x: 0.947, y: 0.58, width: 0.022, height: 0.26)],
        [CGRect(x: 0.126, y: 0.73, width: 0.026, height: 0.18),
         CGRect(x: 0.19, y: 0.64, width: 0.031, height: 0.25),
         CGRect(x: 0.237, y: 0.65, width: 0.036, height: 0.24),
         CGRect(x: 0.413, y: 0.7, width: 0.025, height: 0.19),
         CGRect(x: 0.474, y: 0.65, width: 0.028, height: 0.24),
         CGRect(x: 0.516, y: 0.58, width: 0.027, height: 0.28),
         CGRect(x: 0.582, y: 0.68, width: 0.024, height: 0.22),
         CGRect(x: 0.64, y: 0.62, width: 0.03, height: 0.27),
         CGRect(x: 0.699, y: 0.49, width: 0.027, height: 0.35),
         CGRect(x: 0.79, y: 0.83, width: 0.037, height: 0.08),
         CGRect(x: 0.82, y: 0.26, width: 0.024, height: 0.51),
         CGRect(x: 0.916, y: 0.68, width: 0.02, height: 0.21),
         CGRect(x: 0.958, y: 0.67, width: 0.025, height: 0.23)],
        [CGRect(x: 0.038, y: 0.73, width: 0.024, height: 0.18),
         CGRect(x: 0.107, y: 0.73, width: 0.028, height: 0.18),
         CGRect(x: 0.208, y: 0.65, width: 0.039, height: 0.24),
         CGRect(x: 0.267, y: 0.49, width: 0.031, height: 0.4),
         CGRect(x: 0.318, y: 0.77, width: 0.032, height: 0.15),
         CGRect(x: 0.382, y: 0.68, width: 0.029, height: 0.22),
         CGRect(x: 0.491, y: 0.38, width: 0.031, height: 0.49),
         CGRect(x: 0.466, y: 0.55, width: 0.02, height: 0.34),
         CGRect(x: 0.528, y: 0.55, width: 0.016, height: 0.34),
         CGRect(x: 0.635, y: 0.66, width: 0.02, height: 0.24),
         CGRect(x: 0.702, y: 0.77, width: 0.028, height: 0.14),
         CGRect(x: 0.773, y: 0.73, width: 0.032, height: 0.18),
         CGRect(x: 0.883, y: 0.57, width: 0.031, height: 0.33),
         CGRect(x: 0.944, y: 0.73, width: 0.028, height: 0.17)],
        [CGRect(x: 0.032, y: 0.79, width: 0.027, height: 0.12),
         CGRect(x: 0.085, y: 0.59, width: 0.033, height: 0.31),
         CGRect(x: 0.14, y: 0.81, width: 0.04, height: 0.11),
         CGRect(x: 0.208, y: 0.77, width: 0.027, height: 0.14),
         CGRect(x: 0.303, y: 0.56, width: 0.035, height: 0.34),
         CGRect(x: 0.426, y: 0.25, width: 0.033, height: 0.13),
         CGRect(x: 0.419, y: 0.39, width: 0.047, height: 0.17),
         CGRect(x: 0.413, y: 0.57, width: 0.064, height: 0.33),
         CGRect(x: 0.56, y: 0.57, width: 0.033, height: 0.33),
         CGRect(x: 0.638, y: 0.67, width: 0.034, height: 0.22),
         CGRect(x: 0.726, y: 0.62, width: 0.027, height: 0.28),
         CGRect(x: 0.823, y: 0.48, width: 0.032, height: 0.41),
         CGRect(x: 0.907, y: 0.59, width: 0.03, height: 0.31)]
    ]
    // Deterministic occupancy avoids random flicker when the UI refreshes.
    private static let windows: [[Window]] = (0..<4).map { makeWindows(city: $0) }
    private static func makeWindows(city: Int) -> [Window] {
        var result: [Window] = []
        for (building, rect) in facades[city].enumerated() {
            var row = 0
            for y in stride(from: rect.minY, to: rect.maxY, by: 0.0105) {
                var column = 0
                for x in stride(from: rect.minX, to: rect.maxX, by: 0.0058) {
                    let identifier: Int = city * 100_003 + building * 7_919 + row * 197 + column * 29 + 1
                    var seed = UInt64(identifier)
                    seed = (seed ^ (seed >> 13)) &* 1_274_126_177
                    let occupancy = Double(seed % 1000) / 1000
                    if occupancy < 0.19 + Double(building % 4) * 0.035 {
                        let warmth: Bool = seed % 5 < 2
                        let brightness: Double = 0.55 + Double((seed >> 9) % 40) / 100.0
                        let width: CGFloat = seed % 7 == 0 ? 0.0032 : 0.0018
                        result.append(Window(point: CGPoint(x: x, y: y), warmth: warmth, brightness: brightness, width: width))
                    }
                    column += 1
                }
                row += 1
            }
        }
        return result
    }
    var body: some View {
        Canvas { context, size in
            for window in Self.windows[min(max(city, 0), 3)] {
                let center = CGPoint(x: window.point.x * size.width, y: window.point.y * size.height)
                let color = window.warmth ? Color(red: 1, green: 0.79, blue: 0.40) : Color(red: 1, green: 0.95, blue: 0.79)
                let radius: CGFloat = window.warmth ? 3.1 : 2.2
                let glow = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(glow, with: .radialGradient(Gradient(colors: [color.opacity(window.brightness * 0.22), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
                let pane = CGRect(x: center.x, y: center.y, width: max(0.8, size.width * window.width), height: max(1, size.height * 0.0029))
                context.fill(Path(roundedRect: pane, cornerRadius: 0.3), with: .color(color.opacity(window.brightness)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ConnectionOrb: View {
    var connected: Bool
    var busy: Bool
    var recovery: Bool
    var animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    var body: some View {
        ZStack {
            if connected {
                Circle().fill(Palette.electric.opacity(0.19)).frame(width: 235, height: 235).blur(radius: 35)
                    .scaleEffect(breathing ? 1.08 : 0.94)
                Circle().stroke(Palette.electric.opacity(breathing ? 0.08 : 0.23), lineWidth: 1)
                    .frame(width: 211, height: 211).scaleEffect(breathing ? 1.07 : 0.96)
                Circle().trim(from: 0.04, to: 0.77)
                    .stroke(AngularGradient(colors: [.clear, Palette.electric.opacity(0.25), .white.opacity(0.9), .clear], center: .center), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 193, height: 193).rotationEffect(.degrees(-65))
                Circle().fill(.white).frame(width: 4, height: 4).offset(x: 73, y: -63)
                    .shadow(color: Palette.electric, radius: 9)
            }
            Circle().fill(LinearGradient(colors: connected
                ? [Color(red: 0.69, green: 0.88, blue: 1), Color(red: 0.28, green: 0.59, blue: 0.88), Color(red: 0.12, green: 0.32, blue: 0.58)]
                : [.white, Palette.ice], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 158, height: 158)
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: connected ? Palette.electric.opacity(0.24) : Palette.blue.opacity(0.12), radius: connected ? 33 : 18, x: 0, y: 9)
            Circle().stroke(.white.opacity(connected ? 0.23 : 0.6), lineWidth: 0.8).frame(width: 144, height: 144)
            if busy { ProgressView().controlSize(.large).tint(Palette.blue) }
            else {
                Image(systemName: connected ? "checkmark" : recovery ? "arrow.counterclockwise" : "power")
                    .font(.system(size: connected ? 53 : 45, weight: .light))
                    .foregroundStyle(connected ? Color.white : Palette.blue)
                    .shadow(color: connected ? Color.white.opacity(0.3) : .clear, radius: 12)
            }
        }.frame(width: 236, height: 226)
            .allowsHitTesting(false).accessibilityHidden(true)
            .onAppear { updateAnimation() }
            .onChange(of: connected) { _ in updateAnimation() }
            .onChange(of: reduceMotion) { _ in updateAnimation() }
    }
    private func updateAnimation() {
        if connected && animate && !reduceMotion {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { breathing = false }
        }
    }
}
