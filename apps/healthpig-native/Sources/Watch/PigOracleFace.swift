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
        VStack(spacing: 0) {
            GeometryReader { bounds in
                Image(cover.image)
                    .resizable().scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
                .frame(height: 94)
                .overlay(alignment: art.flipped ? .bottomLeading : .bottomTrailing) {
                    Image(seals[art.ornament]).resizable().scaledToFit()
                        .frame(width: 37, height: 37)
                        .rotationEffect(.degrees(art.flipped ? -10 : 10))
                        .padding(4).accessibilityHidden(true)
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

            VStack(spacing: 3) {
                Text(card.title).font(.headline.bold()).foregroundStyle(cover.title)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("divination.card-title")
                Text(card.prompt).font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("divination.card-prompt")
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(cover.ink)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(cover.title.opacity(0.35))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("divination.face")
    }
}
