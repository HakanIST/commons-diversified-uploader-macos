import SwiftUI

/// Açılış animasyonu: simge yaylanarak gelir, tarama çizgisi formanın üzerinden geçer, başlık belirir.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var appear = false
    @State private var scan = false
    @State private var showTitle = false
    @State private var showTagline = false
    @State private var drift = false
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            // Yavaşça kayan ışık lekeleri
            Circle().fill(Theme.amber.opacity(0.28)).frame(width: 520).blur(radius: 120).offset(x: drift ? 260 : -220, y: drift ? -160 : 180)
            Circle().fill(Color.cyan.opacity(0.25)).frame(width: 460).blur(radius: 110).offset(x: drift ? -280 : 240, y: drift ? 200 : -140)

            VStack(spacing: 26) {
                ZStack {
                    Image("Mark").resizable().interpolation(.high).frame(width: 190, height: 190)
                    // Numara tanımayı çağrıştıran tarama çizgisi
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.clear, Theme.amber, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 150, height: 3)
                        .shadow(color: Theme.amber, radius: 8)
                        .offset(y: scan ? 52 : -52)
                        .opacity(appear ? 0.95 : 0)
                }
                .scaleEffect(appear ? 1 : 0.55)
                .opacity(appear ? 1 : 0)
                .rotation3DEffect(.degrees(appear ? 0 : -24), axis: (x: 1, y: 0, z: 0))

                VStack(spacing: 8) {
                    Text("Commons Diversified Uploader")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(showTitle ? 1 : 0).offset(y: showTitle ? 0 : 14)
                    Text("Forma numarasından oyuncuya, oyuncudan kategoriye")
                        .font(.title3).foregroundStyle(.white.opacity(0.8))
                        .opacity(showTagline ? 1 : 0).offset(y: showTagline ? 0 : 10)
                }
                Capsule().fill(.white.opacity(0.18)).frame(width: 220, height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 220 * progress, height: 4) }
                    .opacity(showTagline ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.6)) { drift = true }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.62).delay(0.15)) { appear = true }
            withAnimation(.easeInOut(duration: 1.1).repeatCount(3, autoreverses: true).delay(0.8)) { scan = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.9)) { showTitle = true }
            withAnimation(.easeOut(duration: 0.6).delay(1.3)) { showTagline = true }
            withAnimation(.easeInOut(duration: 2.0).delay(1.4)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { onFinish() }
        }
    }
}
