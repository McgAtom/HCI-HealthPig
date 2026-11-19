import SwiftUI

struct PigOracleFace: View {
    let card: DivinationCard
    let mood: String?
    let art: DivinationArtwork
    let pig: PigCard?

    private static let ink = Color(red: 0.075, green: 0.06, blue: 0.10)
    private static let palettes: [(paper: Color, foil: Color)] = [
        (Color(red: 0.30, green: 0.17, blue: 0.34), Color(red: 0.98, green: 0.72, blue: 0.90)),
        (Color(red: 0.13, green: 0.29, blue: 0.29), Color(red: 0.66, green: 0.94, blue: 0.85)),
        (Color(red: 0.29, green: 0.19, blue: 0.22), Color(red: 1.00, green: 0.80, blue: 0.65)),
        (Color(red: 0.17, green: 0.21, blue: 0.38), Color(red: 0.76, green: 0.80, blue: 1.00))
    ]
    private static let ornaments = ["sparkle", "moon.stars.fill", "star.fill", "heart.fill", "leaf.fill", "sun.max.fill"]

    private var palette: (paper: Color, foil: Color) { Self.palettes[art.palette] }

    var body: some View {
        let paper = RoundedRectangle(cornerRadius: 17)
        VStack(spacing: 2) {
            illustration
                .overlay(alignment: .topLeading) {
                    if let mood {
                        Text(mood).font(.caption2.weight(.semibold)).lineLimit(1)
                            .frame(maxWidth: 52, alignment: .leading)
                            .foregroundStyle(palette.foil)
                            .accessibilityIdentifier("watch.mood-recorded")
                    }
                }
            Text(card.title).font(.headline.bold()).foregroundStyle(palette.foil)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("divination.card-title")
            Text(card.prompt).font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("divination.card-prompt")
        }
        .padding(.horizontal, 11).padding(.vertical, 7).frame(maxWidth: .infinity)
        .background {
            paper.fill(.linearGradient(colors: [palette.paper, Self.ink], startPoint: .top, endPoint: .bottom))
            paper.strokeBorder(palette.foil.opacity(0.55))
            RoundedRectangle(cornerRadius: 13).strokeBorder(palette.foil.opacity(0.15)).padding(4)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("divination.face")
    }

    private var illustration: some View {
        ZStack {
            switch art.frame {
            case .orbit:
                Ellipse().strokeBorder(palette.foil.opacity(0.38), lineWidth: 0.8)
                    .frame(width: 83, height: 33).rotationEffect(.degrees(art.flipped ? 17 : -17))
                Ellipse().strokeBorder(palette.foil.opacity(0.24), lineWidth: 0.8)
                    .frame(width: 72, height: 29).rotationEffect(.degrees(art.flipped ? -13 : 13))
            case .garden:
                HStack(spacing: 45) {
                    Image(systemName: "leaf.fill").rotationEffect(.degrees(-24))
                    Image(systemName: "leaf.fill").scaleEffect(x: -1, y: 1).rotationEffect(.degrees(24))
                }.font(.title3).foregroundStyle(palette.foil.opacity(0.36))
            case .dawn:
                Circle().strokeBorder(palette.foil.opacity(0.43), lineWidth: 0.8).frame(width: 47)
                Circle().strokeBorder(palette.foil.opacity(0.25), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    .frame(width: 55)
            }

            if let pig {
                Image(pig.assetName).resizable().scaledToFit().frame(width: 52, height: 52)
                    .shadow(color: Self.ink, radius: 4, y: 3)
            } else {
                Image(systemName: card.symbol).font(.system(size: 31)).foregroundStyle(palette.foil)
            }

            Image(systemName: Self.ornaments[art.ornament]).font(.caption.weight(.semibold))
                .foregroundStyle(palette.foil).offset(x: art.flipped ? 48 : -48, y: art.flipped ? -13 : 13)
            Image(systemName: card.symbol).font(.caption.weight(.semibold))
                .foregroundStyle(palette.foil).offset(x: art.flipped ? -45 : 45, y: art.flipped ? 13 : -13)
            Image(systemName: "sparkle").font(.system(size: 6))
                .foregroundStyle(palette.foil.opacity(0.77)).offset(x: art.flipped ? 52 : -52, y: 6)
        }.frame(height: 54).frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}
