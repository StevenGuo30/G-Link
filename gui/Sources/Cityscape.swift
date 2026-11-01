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
