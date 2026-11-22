import SwiftUI

struct LevelMeter: View {
    var levelDB: Float
    var thresholdDB: Float?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat(AudioLevel.meterFraction(levelDB))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * fraction)
                    }
                if let thresholdDB {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: width * CGFloat(AudioLevel.meterFraction(thresholdDB)) - 1)
                        .help("Silence threshold")
                }
            }
        }
        .frame(height: 12)
        .animation(.linear(duration: 0.08), value: levelDB)
        .accessibilityLabel("Audio level")
        .accessibilityValue(levelDB <= -100 ? "silent" : "\(Int(levelDB)) decibels")
    }
}
