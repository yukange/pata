import SwiftUI

// MARK: - Path Shapes (828 x 816 Coordinate Space)

public struct CardBackShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 166, y: 343))
        path.addCurve(to: CGPoint(x: 204, y: 318), control1: CGPoint(x: 176, y: 330), control2: CGPoint(x: 188, y: 322))
        path.addCurve(to: CGPoint(x: 254, y: 319), control1: CGPoint(x: 221, y: 313), control2: CGPoint(x: 237, y: 314))
        path.addLine(to: CGPoint(x: 477, y: 365))
        path.addCurve(to: CGPoint(x: 579, y: 475), control1: CGPoint(x: 517, y: 374), control2: CGPoint(x: 550, y: 414))
        path.addCurve(to: CGPoint(x: 567, y: 586), control1: CGPoint(x: 604, y: 527), control2: CGPoint(x: 601, y: 566))
        path.addCurve(to: CGPoint(x: 533, y: 602), control1: CGPoint(x: 559, y: 592), control2: CGPoint(x: 546, y: 597))
        path.addLine(to: CGPoint(x: 344, y: 668))
        path.addCurve(to: CGPoint(x: 243, y: 630), control1: CGPoint(x: 297, y: 683), control2: CGPoint(x: 265, y: 663))
        path.addCurve(to: CGPoint(x: 177, y: 490), control1: CGPoint(x: 222, y: 596), control2: CGPoint(x: 198, y: 538))
        path.addLine(to: CGPoint(x: 143, y: 408))
        path.addCurve(to: CGPoint(x: 166, y: 343), control1: CGPoint(x: 132, y: 375), control2: CGPoint(x: 150, y: 354))
        path.closeSubpath()
        return path
    }
}

public struct CardMiddleShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 211, y: 279))
        path.addCurve(to: CGPoint(x: 266, y: 275), control1: CGPoint(x: 231, y: 270), control2: CGPoint(x: 248, y: 269))
        path.addLine(to: CGPoint(x: 479, y: 326))
        path.addCurve(to: CGPoint(x: 575, y: 441), control1: CGPoint(x: 523, y: 340), control2: CGPoint(x: 553, y: 380))
        path.addCurve(to: CGPoint(x: 591, y: 562), control1: CGPoint(x: 597, y: 496), control2: CGPoint(x: 610, y: 532))
        path.addCurve(to: CGPoint(x: 551, y: 588), control1: CGPoint(x: 584, y: 573), control2: CGPoint(x: 571, y: 581))
        path.addLine(to: CGPoint(x: 405, y: 625))
        path.addCurve(to: CGPoint(x: 295, y: 586), control1: CGPoint(x: 354, y: 642), control2: CGPoint(x: 320, y: 626))
        path.addCurve(to: CGPoint(x: 220, y: 442), control1: CGPoint(x: 266, y: 542), control2: CGPoint(x: 245, y: 499))
        path.addCurve(to: CGPoint(x: 193, y: 304), control1: CGPoint(x: 193, y: 382), control2: CGPoint(x: 184, y: 345))
        path.addCurve(to: CGPoint(x: 211, y: 279), control1: CGPoint(x: 196, y: 292), control2: CGPoint(x: 201, y: 284))
        path.closeSubpath()
        return path
    }
}

public struct CardFrontShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 310, y: 224))
        path.addCurve(to: CGPoint(x: 362, y: 236), control1: CGPoint(x: 331, y: 224), control2: CGPoint(x: 345, y: 229))
        path.addLine(to: CGPoint(x: 484, y: 279))
        path.addCurve(to: CGPoint(x: 560, y: 366), control1: CGPoint(x: 527, y: 295), control2: CGPoint(x: 539, y: 316))
        path.addCurve(to: CGPoint(x: 591, y: 432), control1: CGPoint(x: 569, y: 388), control2: CGPoint(x: 579, y: 409))
        path.addCurve(to: CGPoint(x: 664, y: 487), control1: CGPoint(x: 607, y: 456), control2: CGPoint(x: 639, y: 470))
        path.addCurve(to: CGPoint(x: 661, y: 538), control1: CGPoint(x: 688, y: 504), control2: CGPoint(x: 684, y: 523))
        path.addCurve(to: CGPoint(x: 610, y: 556), control1: CGPoint(x: 648, y: 547), control2: CGPoint(x: 633, y: 550))
        path.addLine(to: CGPoint(x: 453, y: 583))
        path.addCurve(to: CGPoint(x: 342, y: 544), control1: CGPoint(x: 402, y: 592), control2: CGPoint(x: 366, y: 577))
        path.addCurve(to: CGPoint(x: 260, y: 383), control1: CGPoint(x: 307, y: 496), control2: CGPoint(x: 285, y: 444))
        path.addCurve(to: CGPoint(x: 240, y: 269), control1: CGPoint(x: 243, y: 341), control2: CGPoint(x: 234, y: 301))
        path.addCurve(to: CGPoint(x: 310, y: 224), control1: CGPoint(x: 245, y: 238), control2: CGPoint(x: 272, y: 221))
        path.closeSubpath()
        return path
    }
}

public struct CardBackSpineShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 150, y: 400))
        p.addCurve(to: CGPoint(x: 245, y: 630), control1: CGPoint(x: 159, y: 445), control2: CGPoint(x: 202, y: 551))
        p.addCurve(to: CGPoint(x: 346, y: 664), control1: CGPoint(x: 271, y: 669), control2: CGPoint(x: 304, y: 682))
        return p
    }
}

public struct CardMiddleSpineShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 202, y: 304))
        p.addCurve(to: CGPoint(x: 228, y: 452), control1: CGPoint(x: 191, y: 347), control2: CGPoint(x: 203, y: 397))
        p.addCurve(to: CGPoint(x: 307, y: 595), control1: CGPoint(x: 255, y: 511), control2: CGPoint(x: 281, y: 559))
        p.addCurve(to: CGPoint(x: 407, y: 621), control1: CGPoint(x: 331, y: 629), control2: CGPoint(x: 366, y: 639))
        return p
    }
}

public struct CardFrontSpineShape1: Shape {
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 308, y: 227))
        p.addCurve(to: CGPoint(x: 246, y: 270), control1: CGPoint(x: 277, y: 223), control2: CGPoint(x: 252, y: 237))
        p.addCurve(to: CGPoint(x: 270, y: 402), control1: CGPoint(x: 241, y: 302), control2: CGPoint(x: 251, y: 352))
        p.addCurve(to: CGPoint(x: 346, y: 547), control1: CGPoint(x: 290, y: 454), control2: CGPoint(x: 317, y: 515))
        p.addCurve(to: CGPoint(x: 451, y: 582), control1: CGPoint(x: 370, y: 581), control2: CGPoint(x: 404, y: 589))
        return p
    }
}

public struct CardFrontSpineShape2: Shape {
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 341, y: 545))
        p.addCurve(to: CGPoint(x: 453, y: 586), control1: CGPoint(x: 368, y: 582), control2: CGPoint(x: 403, y: 592))
        p.addLine(to: CGPoint(x: 611, y: 560))
        p.addCurve(to: CGPoint(x: 664, y: 539), control1: CGPoint(x: 634, y: 555), control2: CGPoint(x: 648, y: 550))
        return p
    }
}

// MARK: - Motion Values

struct CardMotionValues {
    var offsetY: CGFloat = 0
    var scaleX: CGFloat = 1.0
    var scaleY: CGFloat = 1.0
    var rotation: Angle = .zero
    var opacity: Double = 1.0
}

struct SparkleMotionValues {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0
    var opacity: Double = 1.0
    var glowOpacity: Double = 0.14
}

// MARK: - Gradients

private let purpleGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 255/255, green: 157/255, blue: 64/255), location: 0.0),
        .init(color: Color(red: 255/255, green: 93/255, blue: 174/255), location: 0.4),
        .init(color: Color(red: 173/255, green: 80/255, blue: 240/255), location: 0.74),
        .init(color: Color(red: 96/255, green: 111/255, blue: 251/255), location: 1.0)
    ],
    startPoint: UnitPoint(x: 0, y: 0.1),
    endPoint: UnitPoint(x: 1, y: 1)
)

private let yellowGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 255/255, green: 238/255, blue: 87/255), location: 0.0),
        .init(color: Color(red: 255/255, green: 198/255, blue: 59/255), location: 0.3),
        .init(color: Color(red: 255/255, green: 156/255, blue: 70/255), location: 0.69),
        .init(color: Color(red: 255/255, green: 187/255, blue: 118/255), location: 1.0)
    ],
    startPoint: UnitPoint(x: 0.1, y: 0.03),
    endPoint: UnitPoint(x: 0.83, y: 1.0)
)

private let whiteLeafGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 255/255, green: 255/255, blue: 247/255), location: 0.0),
        .init(color: Color(red: 255/255, green: 246/255, blue: 237/255), location: 0.26),
        .init(color: Color(red: 249/255, green: 245/255, blue: 254/255), location: 0.57),
        .init(color: Color(red: 232/255, green: 236/255, blue: 255/255), location: 0.83),
        .init(color: Color(red: 255/255, green: 253/255, blue: 251/255), location: 1.0)
    ],
    startPoint: UnitPoint(x: 0.15, y: 0),
    endPoint: UnitPoint(x: 0.92, y: 1.0)
)

private let leafEdgeGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 226/255, green: 218/255, blue: 240/255), location: 0.0),
        .init(color: Color(red: 255/255, green: 247/255, blue: 243/255), location: 0.6),
        .init(color: Color(red: 225/255, green: 213/255, blue: 255/255), location: 1.0)
    ],
    startPoint: UnitPoint(x: 0.1, y: 0),
    endPoint: UnitPoint(x: 0.5, y: 1.0)
)

private let sparkYellowGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 255/255, green: 232/255, blue: 67/255), location: 0.0),
        .init(color: Color(red: 255/255, green: 189/255, blue: 23/255), location: 0.57),
        .init(color: Color(red: 255/255, green: 142/255, blue: 37/255), location: 1.0)
    ],
    startPoint: UnitPoint(x: 0, y: 0),
    endPoint: UnitPoint(x: 1, y: 1)
)

// MARK: - Subviews

struct CardBackView: View {
    let trigger: LogoAnimationTrigger
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Shadow
            CardBackShape()
                .fill(Color(red: 128/255, green: 58/255, blue: 205/255).opacity(0.22))
                .offset(x: 5, y: 12)
                .blur(radius: 16)

            // Body
            CardBackShape()
                .fill(purpleGradient)
                .overlay(
                    CardBackShape()
                        .stroke(Color(red: 247/255, green: 182/255, blue: 229/255).opacity(0.55), lineWidth: 2.4)
                )

            // Spine
            CardBackSpineShape()
                .stroke(Color(red: 255/255, green: 209/255, blue: 232/255).opacity(0.42), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .keyframeAnimator(initialValue: CardMotionValues(), trigger: trigger) { content, val in
            content
                .offset(y: val.offsetY)
                .scaleEffect(x: val.scaleX, y: val.scaleY, anchor: UnitPoint(x: 0.5, y: 0.85))
                .rotationEffect(val.rotation, anchor: UnitPoint(x: 0.5, y: 0.85))
                .opacity(val.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetY) {
                if reduceMotion {
                    MoveKeyframe(0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(12)
                        CubicKeyframe(-2, duration: 0.338)
                        CubicKeyframe(0, duration: 0.182)
                    case .success:
                        CubicKeyframe(5.0, duration: 0.154)
                        CubicKeyframe(-4.0, duration: 0.182)
                        CubicKeyframe(1.0, duration: 0.189)
                        CubicKeyframe(0, duration: 0.175)
                    case .interactive:
                        CubicKeyframe(40.8, duration: 0.100)
                        CubicKeyframe(-57.1, duration: 0.158)
                        CubicKeyframe(16.3, duration: 0.145)
                        CubicKeyframe(0, duration: 0.157)
                    case .idle:
                        MoveKeyframe(0)
                    }
                }
            }
            KeyframeTrack(\.scaleX) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.975)
                        CubicKeyframe(1.008, duration: 0.338)
                        CubicKeyframe(1.0, duration: 0.182)
                    case .success:
                        CubicKeyframe(0.985, duration: 0.154)
                        CubicKeyframe(1.015, duration: 0.182)
                        CubicKeyframe(0.998, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.175)
                    case .interactive:
                        CubicKeyframe(1.04, duration: 0.100)
                        CubicKeyframe(0.98, duration: 0.158)
                        CubicKeyframe(1.01, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.157)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.scaleY) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.975)
                        CubicKeyframe(1.008, duration: 0.338)
                        CubicKeyframe(1.0, duration: 0.182)
                    case .success:
                        CubicKeyframe(0.985, duration: 0.154)
                        CubicKeyframe(1.015, duration: 0.182)
                        CubicKeyframe(0.998, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.175)
                    case .interactive:
                        CubicKeyframe(0.92, duration: 0.100)
                        CubicKeyframe(1.04, duration: 0.158)
                        CubicKeyframe(0.98, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.157)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.rotation) {
                if reduceMotion {
                    MoveKeyframe(Angle.zero)
                } else {
                    switch trigger {
                    case .interactive:
                        CubicKeyframe(Angle.degrees(-2), duration: 0.100)
                        CubicKeyframe(Angle.degrees(-5), duration: 0.158)
                        CubicKeyframe(Angle.degrees(-1), duration: 0.145)
                        CubicKeyframe(Angle.zero, duration: 0.157)
                    default:
                        MoveKeyframe(Angle.zero)
                    }
                }
            }
            KeyframeTrack(\.opacity) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.15)
                        CubicKeyframe(1.0, duration: 0.338)
                        LinearKeyframe(1.0, duration: 0.182)
                    default:
                        MoveKeyframe(1.0)
                    }
                }
            }
        }
    }
}

struct CardMiddleView: View {
    let trigger: LogoAnimationTrigger
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Shadow 1
            CardMiddleShape()
                .fill(Color(red: 221/255, green: 116/255, blue: 127/255).opacity(0.22))
                .offset(x: 3, y: 7)
                .blur(radius: 10)

            // Shadow 2
            CardMiddleShape()
                .fill(Color(red: 236/255, green: 151/255, blue: 112/255).opacity(0.4))
                .offset(x: 1.5, y: 5)

            // Body
            CardMiddleShape()
                .fill(yellowGradient)
                .overlay(
                    CardMiddleShape()
                        .stroke(Color(red: 255/255, green: 229/255, blue: 150/255), lineWidth: 3.1)
                )

            // Spine
            CardMiddleSpineShape()
                .stroke(Color(red: 255/255, green: 239/255, blue: 186/255).opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .keyframeAnimator(initialValue: CardMotionValues(), trigger: trigger) { content, val in
            content
                .offset(y: val.offsetY)
                .scaleEffect(x: val.scaleX, y: val.scaleY, anchor: UnitPoint(x: 0.5, y: 0.85))
                .rotationEffect(val.rotation, anchor: UnitPoint(x: 0.5, y: 0.85))
                .opacity(val.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetY) {
                if reduceMotion {
                    MoveKeyframe(0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(16)
                        LinearKeyframe(16, duration: 0.045)
                        CubicKeyframe(-3, duration: 0.351)
                        CubicKeyframe(0, duration: 0.189)
                    case .success:
                        LinearKeyframe(0, duration: 0.025)
                        CubicKeyframe(6.0, duration: 0.154)
                        CubicKeyframe(-4.5, duration: 0.182)
                        CubicKeyframe(1.2, duration: 0.189)
                        CubicKeyframe(0, duration: 0.150)
                    case .interactive:
                        LinearKeyframe(0, duration: 0.020)
                        CubicKeyframe(40.8, duration: 0.100)
                        CubicKeyframe(-97.9, duration: 0.158)
                        CubicKeyframe(16.3, duration: 0.145)
                        CubicKeyframe(0, duration: 0.137)
                    case .idle:
                        MoveKeyframe(0)
                    }
                }
            }
            KeyframeTrack(\.scaleX) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.965)
                        LinearKeyframe(0.965, duration: 0.045)
                        CubicKeyframe(1.012, duration: 0.351)
                        CubicKeyframe(1.0, duration: 0.189)
                    case .success:
                        LinearKeyframe(1.0, duration: 0.025)
                        CubicKeyframe(0.980, duration: 0.154)
                        CubicKeyframe(1.018, duration: 0.182)
                        CubicKeyframe(0.997, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.150)
                    case .interactive:
                        LinearKeyframe(1.0, duration: 0.020)
                        CubicKeyframe(1.04, duration: 0.100)
                        CubicKeyframe(0.98, duration: 0.158)
                        CubicKeyframe(1.01, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.137)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.scaleY) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.965)
                        LinearKeyframe(0.965, duration: 0.045)
                        CubicKeyframe(1.012, duration: 0.351)
                        CubicKeyframe(1.0, duration: 0.189)
                    case .success:
                        LinearKeyframe(1.0, duration: 0.025)
                        CubicKeyframe(0.980, duration: 0.154)
                        CubicKeyframe(1.018, duration: 0.182)
                        CubicKeyframe(0.997, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.150)
                    case .interactive:
                        LinearKeyframe(1.0, duration: 0.020)
                        CubicKeyframe(0.92, duration: 0.100)
                        CubicKeyframe(1.04, duration: 0.158)
                        CubicKeyframe(0.98, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.137)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.rotation) {
                if reduceMotion {
                    MoveKeyframe(Angle.zero)
                } else {
                    switch trigger {
                    case .interactive:
                        LinearKeyframe(Angle.zero, duration: 0.020)
                        CubicKeyframe(Angle.degrees(-2), duration: 0.100)
                        CubicKeyframe(Angle.degrees(-2), duration: 0.158)
                        CubicKeyframe(Angle.degrees(-1), duration: 0.145)
                        CubicKeyframe(Angle.zero, duration: 0.137)
                    default:
                        MoveKeyframe(Angle.zero)
                    }
                }
            }
            KeyframeTrack(\.opacity) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.15)
                        LinearKeyframe(0.15, duration: 0.045)
                        CubicKeyframe(1.0, duration: 0.351)
                        LinearKeyframe(1.0, duration: 0.189)
                    default:
                        MoveKeyframe(1.0)
                    }
                }
            }
        }
    }
}

struct CardFrontView: View {
    let trigger: LogoAnimationTrigger
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Shadow 1
            CardFrontShape()
                .fill(Color(red: 158/255, green: 143/255, blue: 195/255).opacity(0.17))
                .offset(x: 5, y: 9)
                .blur(radius: 10)

            // Shadow 2
            CardFrontShape()
                .fill(Color(red: 215/255, green: 208/255, blue: 242/255).opacity(0.72))
                .offset(x: 1, y: 5)

            // Body
            CardFrontShape()
                .fill(whiteLeafGradient)
                .overlay(
                    CardFrontShape()
                        .stroke(leafEdgeGradient, lineWidth: 3.5)
                )

            // Spines
            CardFrontSpineShape1()
                .stroke(Color.white.opacity(0.82), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            CardFrontSpineShape2()
                .stroke(Color(red: 198/255, green: 190/255, blue: 239/255).opacity(0.4), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        .keyframeAnimator(initialValue: CardMotionValues(), trigger: trigger) { content, val in
            content
                .offset(y: val.offsetY)
                .scaleEffect(x: val.scaleX, y: val.scaleY, anchor: UnitPoint(x: 0.5, y: 0.85))
                .rotationEffect(val.rotation, anchor: UnitPoint(x: 0.5, y: 0.85))
                .opacity(val.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetY) {
                if reduceMotion {
                    MoveKeyframe(0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(20)
                        LinearKeyframe(20, duration: 0.090)
                        CubicKeyframe(-4, duration: 0.364)
                        CubicKeyframe(0, duration: 0.196)
                    case .success:
                        LinearKeyframe(0, duration: 0.050)
                        CubicKeyframe(7.5, duration: 0.154)
                        CubicKeyframe(-5.5, duration: 0.182)
                        CubicKeyframe(1.5, duration: 0.189)
                        CubicKeyframe(0, duration: 0.125)
                    case .interactive:
                        LinearKeyframe(0, duration: 0.040)
                        CubicKeyframe(40.8, duration: 0.100)
                        CubicKeyframe(-146.9, duration: 0.158)
                        CubicKeyframe(16.3, duration: 0.145)
                        CubicKeyframe(0, duration: 0.117)
                    case .idle:
                        MoveKeyframe(0)
                    }
                }
            }
            KeyframeTrack(\.scaleX) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.950)
                        LinearKeyframe(0.950, duration: 0.090)
                        CubicKeyframe(1.018, duration: 0.364)
                        CubicKeyframe(1.0, duration: 0.196)
                    case .success:
                        LinearKeyframe(1.0, duration: 0.050)
                        CubicKeyframe(0.980, duration: 0.154)
                        CubicKeyframe(1.020, duration: 0.182)
                        CubicKeyframe(0.996, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.125)
                    case .interactive:
                        LinearKeyframe(1.0, duration: 0.040)
                        CubicKeyframe(1.04, duration: 0.100)
                        CubicKeyframe(0.98, duration: 0.158)
                        CubicKeyframe(1.01, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.117)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.scaleY) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.950)
                        LinearKeyframe(0.950, duration: 0.090)
                        CubicKeyframe(1.018, duration: 0.364)
                        CubicKeyframe(1.0, duration: 0.196)
                    case .success:
                        LinearKeyframe(1.0, duration: 0.050)
                        CubicKeyframe(0.980, duration: 0.154)
                        CubicKeyframe(1.020, duration: 0.182)
                        CubicKeyframe(0.996, duration: 0.189)
                        CubicKeyframe(1.0, duration: 0.125)
                    case .interactive:
                        LinearKeyframe(1.0, duration: 0.040)
                        CubicKeyframe(0.92, duration: 0.100)
                        CubicKeyframe(1.04, duration: 0.158)
                        CubicKeyframe(0.98, duration: 0.145)
                        CubicKeyframe(1.0, duration: 0.117)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.rotation) {
                if reduceMotion {
                    MoveKeyframe(Angle.zero)
                } else {
                    switch trigger {
                    case .interactive:
                        LinearKeyframe(Angle.zero, duration: 0.040)
                        CubicKeyframe(Angle.degrees(-2), duration: 0.100)
                        CubicKeyframe(Angle.degrees(6), duration: 0.158)
                        CubicKeyframe(Angle.degrees(-1), duration: 0.145)
                        CubicKeyframe(Angle.zero, duration: 0.117)
                    default:
                        MoveKeyframe(Angle.zero)
                    }
                }
            }
            KeyframeTrack(\.opacity) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.15)
                        LinearKeyframe(0.15, duration: 0.090)
                        CubicKeyframe(1.0, duration: 0.364)
                        LinearKeyframe(1.0, duration: 0.196)
                    default:
                        MoveKeyframe(1.0)
                    }
                }
            }
        }
    }
}

struct SparkleRayView: View {
    let index: Int
    let trigger: LogoAnimationTrigger
    let reduceMotion: Bool

    private var baseX: CGFloat {
        switch index {
        case 1: return 511
        case 2: return 597.5
        default: return 653.5
        }
    }

    private var baseY: CGFloat {
        switch index {
        case 1: return 194.5
        case 2: return 223.5
        default: return 339.5
        }
    }

    private var baseRotation: Angle {
        switch index {
        case 1: return .degrees(-1)
        case 2: return .degrees(46)
        default: return .degrees(6)
        }
    }

    private var shootX: CGFloat {
        switch index {
        case 1: return 0
        case 2: return 220
        default: return 300
        }
    }

    private var shootY: CGFloat {
        switch index {
        case 1: return -280
        case 2: return -220
        default: return 24
        }
    }

    private var launchDelay: Double {
        switch index {
        case 1: return 0.240
        case 2: return 0.320
        default: return 0.400
        }
    }

    private var successDelay: Double {
        switch index {
        case 1: return 0.200
        case 2: return 0.280
        default: return 0.360
        }
    }

    private var interactiveDelay: Double {
        switch index {
        case 1: return 0.120
        case 2: return 0.160
        default: return 0.200
        }
    }

    var body: some View {
        ZStack {
            if index == 1 {
                // Glow
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(Color(red: 255/255, green: 153/255, blue: 35/255).opacity(0.14))
                    .frame(width: 44, height: 105)
                    .blur(radius: 7)

                // Ray
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(sparkYellowGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(Color(red: 255/255, green: 226/255, blue: 119/255), lineWidth: 1.5)
                    )
                    .frame(width: 42, height: 103)
            } else if index == 2 {
                // Glow
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 255/255, green: 153/255, blue: 35/255).opacity(0.14))
                    .frame(width: 47, height: 109)
                    .blur(radius: 7)

                // Ray
                RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                    .fill(sparkYellowGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                            .stroke(Color(red: 255/255, green: 226/255, blue: 119/255), lineWidth: 1.5)
                    )
                    .frame(width: 45, height: 105)
            } else {
                // Glow
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 255/255, green: 153/255, blue: 35/255).opacity(0.14))
                    .frame(width: 96, height: 44)
                    .blur(radius: 7)

                // Ray
                RoundedRectangle(cornerRadius: 21.5, style: .continuous)
                    .fill(sparkYellowGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 21.5, style: .continuous)
                            .stroke(Color(red: 255/255, green: 226/255, blue: 119/255), lineWidth: 1.5)
                    )
                    .frame(width: 103, height: 43)
            }
        }
        .rotationEffect(baseRotation)
        .keyframeAnimator(initialValue: SparkleMotionValues(), trigger: trigger) { content, val in
            content
                .offset(x: val.offsetX, y: val.offsetY)
                .scaleEffect(val.scale)
                .opacity(val.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetX) {
                if reduceMotion {
                    MoveKeyframe(0)
                } else {
                    switch trigger {
                    case .interactive:
                        LinearKeyframe(0, duration: interactiveDelay)
                        LinearKeyframe(0, duration: 0.074)
                        CubicKeyframe(shootX, duration: 0.174)
                        CubicKeyframe(0, duration: 0.260)
                        CubicKeyframe(0, duration: 0.112)
                    default:
                        MoveKeyframe(0)
                    }
                }
            }
            KeyframeTrack(\.offsetY) {
                if reduceMotion {
                    MoveKeyframe(0)
                } else {
                    switch trigger {
                    case .interactive:
                        LinearKeyframe(0, duration: interactiveDelay)
                        LinearKeyframe(0, duration: 0.074)
                        CubicKeyframe(shootY, duration: 0.174)
                        CubicKeyframe(0, duration: 0.260)
                        CubicKeyframe(0, duration: 0.112)
                    default:
                        MoveKeyframe(0)
                    }
                }
            }
            KeyframeTrack(\.scale) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0.25)
                        LinearKeyframe(0.25, duration: launchDelay)
                        CubicKeyframe(1.20, duration: 0.169)
                        CubicKeyframe(1.00, duration: 0.091)
                    case .success:
                        LinearKeyframe(1.0, duration: successDelay)
                        CubicKeyframe(1.26, duration: 0.128)
                        CubicKeyframe(1.00, duration: 0.192)
                    case .interactive:
                        LinearKeyframe(1.0, duration: interactiveDelay)
                        CubicKeyframe(0.85, duration: 0.074)
                        CubicKeyframe(1.10, duration: 0.174)
                        CubicKeyframe(1.04, duration: 0.260)
                        CubicKeyframe(1.00, duration: 0.112)
                    case .idle:
                        MoveKeyframe(1.0)
                    }
                }
            }
            KeyframeTrack(\.opacity) {
                if reduceMotion {
                    MoveKeyframe(1.0)
                } else {
                    switch trigger {
                    case .launch:
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: launchDelay)
                        CubicKeyframe(1.0, duration: 0.169)
                        LinearKeyframe(1.0, duration: 0.091)
                    default:
                        MoveKeyframe(1.0)
                    }
                }
            }
        }
        .position(x: baseX, y: baseY)
    }
}

// MARK: - Public Component

public struct PataLogoView: View {
    public var size: CGFloat
    @ObservedObject private var coordinator = LogoAnimationCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        Button(action: {
            coordinator.playInteractive()
        }) {
            ZStack {
                // 底层卡片 (粉紫渐变 + 随动阴影)
                CardBackView(trigger: coordinator.trigger, reduceMotion: reduceMotion)

                // 中层卡片 (橙黄渐变 + 随动阴影)
                CardMiddleView(trigger: coordinator.trigger, reduceMotion: reduceMotion)

                // 顶层卡片 (折叠白卡 + 淡紫描边 + 随动阴影)
                CardFrontView(trigger: coordinator.trigger, reduceMotion: reduceMotion)

                // 三道放射光芒 (辉光 + 实体)
                SparkleRayView(index: 1, trigger: coordinator.trigger, reduceMotion: reduceMotion)
                SparkleRayView(index: 2, trigger: coordinator.trigger, reduceMotion: reduceMotion)
                SparkleRayView(index: 3, trigger: coordinator.trigger, reduceMotion: reduceMotion)
            }
            .frame(width: 828, height: 816)
            .scaleEffect(size / 828.0)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                coordinator.playInteractive()
            }
        }
        .accessibilityLabel("Pata 品牌标识")
    }
}
