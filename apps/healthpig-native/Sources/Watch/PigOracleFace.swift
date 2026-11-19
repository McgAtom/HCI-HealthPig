import SwiftUI

struct PigOracleFace<DailyEntry: View>: View {
    let card: DivinationCard
    let mood: String?
    let art: DivinationArtwork
    @ViewBuilder let dailyEntry: DailyEntry

    private let seals = ["oracle-moon", "oracle-heart", "oracle-leaves"]

    private var cover: (image: String, ink: Color, title: Color) {
        switch art.frame {
        case .orbit:
            ("oracle-orbit", Color(red: 0.125, green: 0.095, blue: 0.20), Color(red: 1, green: 0.85, blue: 0.92))
        case .garden:
            ("oracle-garden", Color(red: 0.06, green: 0.16, blue: 0.14), Color(red: 0.78, green: 0.92, blue: 0.82))
        case .dawn:
            ("oracle-dawn", Color(red: 0.23, green: 0.12, blue: 0.16), Color(red: 1, green: 0.85, blue: 0.69))
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: 86).accessibilityHidden(true)
            Text(card.title).font(.headline.bold()).foregroundStyle(cover.title)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("divination.card-title")
            Text(card.prompt).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("divination.card-prompt")
        }
        .padding(.horizontal, 9).padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .background { illustration }
        .overlay(alignment: art.flipped ? .topLeading : .topTrailing) {
            Image(seals[art.ornament]).resizable().scaledToFit()
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(art.flipped ? -10 : 10))
                .padding(.horizontal, 7).padding(.top, 48)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            if let mood {
                Text(mood).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: 93, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.76), in: Capsule())
                    .padding(.top, 7).padding(.leading, 7)
                    .accessibilityIdentifier("watch.mood-recorded")
            }
        }
        .overlay(alignment: .topTrailing) { dailyEntry }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(cover.title.opacity(0.35))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("divination.face")
    }

    private var illustration: some View {
        GeometryReader { bounds in
            Image(cover.image).resizable().scaledToFill()
                .frame(width: bounds.size.width, height: bounds.size.height)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.36),
                        .init(color: .black.opacity(0.30), location: 0.57),
                        .init(color: cover.ink.opacity(0.77), location: 0.79),
                        .init(color: cover.ink.opacity(0.89), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
