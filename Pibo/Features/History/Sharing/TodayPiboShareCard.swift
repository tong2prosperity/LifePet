import SwiftUI
import UIKit

struct TodayPiboShareCard: View {
    let snapshot: TodayPiboShareSnapshot
    let scene: PiboFlatWorldScene
    let characterImage: UIImage?
    /// Decision 063: the pixel world's card — the portrait is drawn by the stage's own
    /// generators instead of the hand-painted share backgrounds.
    var pixel = false
    var appearance = PiboPixelLook()

    var body: some View {
        Group {
            if pixel { pixelBody } else { legacyBody }
        }
        .frame(width: 320, height: 426.667)
        .background(Color(red: 0.02, green: 0.09, blue: 0.23))
        .clipShape(RoundedRectangle(cornerRadius: pixel ? 0 : 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.petName)，\(snapshot.dateLabel)，\(snapshot.primaryCaption)，\(snapshot.primaryValue)，今天的我，\(snapshot.activityLabel)")
    }

    // MARK: Pixel card (HarmonyPibo `TodayPiboShareSheet.ets`)

    private var pixelBody: some View {
        ZStack(alignment: .topLeading) {
            PixelPortraitView(scene: scene, stateID: snapshot.assetStateID, appearance: appearance)
                .frame(width: 320, height: 426.667)

            // One continuous atmosphere veil keeps the type readable without turning the
            // information into a floating card.
            LinearGradient(colors: [Color(pixelARGB: 0x8F02172B), Color(pixelARGB: 0x0002172B)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
            LinearGradient(colors: [Color(pixelARGB: 0x0002172B), Color(pixelARGB: 0x6602172B)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 66)
                .offset(y: 361)

            VStack(alignment: .leading, spacing: 12) {
                Text("\(snapshot.petName.uppercased()) · \(snapshot.dateLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(pixelARGB: 0xFFF8FAFF))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.primaryCaption)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(pixelARGB: 0xBDF8FAFF))
                    Text(snapshot.primaryValue)
                        .font(.system(size: snapshot.hasHealthFacts ? 38 : 31, weight: .bold))
                        .foregroundStyle(Color(pixelARGB: 0xFFF8FAFF))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let range = snapshot.sleepRange {
                        Text(range)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(pixelARGB: 0xCFF8FAFF))
                            .lineLimit(1)
                    }
                }

                // Without health facts the primary line already is the state; ArkTS skips
                // this block so the same words never print twice.
                if snapshot.hasHealthFacts {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天的我")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color(pixelARGB: 0xBDF8FAFF))
                        Text(snapshot.activityLabel)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(Color(pixelARGB: 0xFFF8FAFF))
                            .lineLimit(1)
                    }
                }

                if snapshot.hasActivityFacts {
                    HStack(spacing: 10) {
                        metric("活动", value: snapshot.activeEnergy.map { "\(Int($0.rounded())) kcal" },
                               progress: snapshot.moveProgress, color: Color(pixelHex: 0xFF7468))
                        metric("运动", value: snapshot.exerciseMinutes.map { "\($0) min" },
                               progress: snapshot.exerciseProgress, color: Color(pixelHex: 0x29D9CF))
                        metric("站立", value: snapshot.standHours.map { "\($0) h" },
                               progress: snapshot.standProgress, color: Color(pixelHex: 0xB7E532))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("PIBO · 今天的状态映照")
                .font(.system(size: 7))
                .foregroundStyle(Color(pixelARGB: 0xB8F8FAFF))
                .tracking(0.6)
                .offset(x: 20, y: 406)
        }
    }

    // MARK: Legacy card

    private var legacyBody: some View {
        ZStack(alignment: .topLeading) {
            Image(scene.resourceName)
                .resizable()
                .scaledToFill()
                .frame(width: 320, height: 426.667)
                .clipped()
            Color(red: 0.01, green: 0.09, blue: 0.17)
                .opacity(0.24)
            Color.black.opacity(0.24)
                .frame(height: 132)
                .frame(maxHeight: .infinity, alignment: .bottom)

            if let characterImage {
                Image(uiImage: characterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 212, height: 212)
                    .position(x: 200, y: 310)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("\(snapshot.petName.uppercased()) · \(snapshot.dateLabel)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.primaryCaption).font(.system(size: 9, weight: .medium))
                    Text(snapshot.primaryValue)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)
                    if let range = snapshot.sleepRange {
                        Text(range).font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                Text("今天的我  ·  \(snapshot.activityLabel)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                if snapshot.hasActivityFacts {
                    HStack(spacing: 10) {
                        metric("活动", value: snapshot.activeEnergy.map { "\(Int($0.rounded())) kcal" }, progress: snapshot.moveProgress, color: .init(red: 1, green: 0.45, blue: 0.41))
                        metric("运动", value: snapshot.exerciseMinutes.map { "\($0) min" }, progress: snapshot.exerciseProgress, color: .init(red: 0.16, green: 0.85, blue: 0.81))
                        metric("站立", value: snapshot.standHours.map { "\($0) h" }, progress: snapshot.standProgress, color: .init(red: 0.72, green: 0.90, blue: 0.20))
                    }
                }
                Text("PIBO · 今天的状态映照")
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .tracking(0.6)
                    .opacity(0.72)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    private func metric(_ title: String, value: String?, progress: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "circle.fill")
                .font(.system(size: 7, weight: .medium))
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
            Text(value ?? "--").font(.system(size: 10, weight: .bold, design: .rounded))
            if let progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.3))
                        Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, progress)))
                    }
                }.frame(height: 3)
            } else {
                Capsule().fill(color).frame(width: 20, height: 2)
            }
        }
        .frame(width: 80, alignment: .leading)
    }
}

extension PiboFlatWorldScene {
    var resourceName: String {
        switch self {
        case .nightClouds: "pibo_share_night_clouds"
        case .dawnCreek: "pibo_share_dawn_creek"
        case .riverValley: "pibo_share_river_valley"
        case .rainGorge: "pibo_share_rain_gorge"
        case .coralDusk: "pibo_share_coral_dusk"
        }
    }

    var localizedTitle: String {
        switch self {
        case .nightClouds: "夜云森林"
        case .dawnCreek: "晨雾溪谷"
        case .riverValley: "晴日河谷"
        case .rainGorge: "暴雨峡谷"
        case .coralDusk: "珊瑚暮岸"
        }
    }
}

private extension Color {
    /// `0xAARRGGBB`, the way the ArkTS side writes its colours.
    init(pixelARGB value: UInt32) {
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: Double((value >> 24) & 0xFF) / 255)
    }
}
