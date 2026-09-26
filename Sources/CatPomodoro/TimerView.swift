import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: TimerModel
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: model.isPresentingBubble ? 10 : 0) {
            if model.isPresentingBubble && model.bubbleOnLeft {
                activeBubble
            }

            // Keep the same pet view alive while bubbles appear or disappear.
            pet
                .id("persistent-timer-pet")

            if model.isPresentingBubble && !model.bubbleOnLeft {
                activeBubble
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var activeBubble: some View {
        if model.showsCompletion {
            CompletionBubble(model: model, pointsLeft: !model.bubbleOnLeft)
        } else if model.showsSettings {
            SettingsBubble(model: model, pointsLeft: !model.bubbleOnLeft)
        } else if let message = model.encouragementMessage {
            EncouragementBubble(
                model: model,
                message: message,
                milestone: model.encouragementMilestone ?? 75,
                pointsLeft: !model.bubbleOnLeft
            )
        } else {
            EmptyView()
        }
    }

    private var pet: some View {
        TimerPetView(model: model, onHide: onHide)
    }
}

struct TimerPetView: View {
    @ObservedObject var model: TimerModel
    let onHide: () -> Void
    @State private var bobbing = false
    @State private var tailSwinging = false
    private let displayScale: CGFloat = 0.60

    var body: some View {
        ZStack {
            ZStack {
                Image(nsImage: PetAssets.catTail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 280, height: 420)
                    // The pivot sits behind the tomato so the join stays hidden.
                    .rotationEffect(
                        .degrees(tailSwinging ? 7 : -7),
                        anchor: UnitPoint(x: 0.50, y: 0.73)
                    )
                    .animation(
                        .easeInOut(duration: 2.8)
                            .repeatForever(autoreverses: true),
                        value: tailSwinging
                    )
                    .position(x: 145, y: 220)

                Image(nsImage: PetAssets.catTimerBody)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 280, height: 420)
                    .shadow(color: .black.opacity(0.18), radius: 9, y: 6)
                    .position(x: 145, y: 220)

                TimerFaceView(model: model)
                    .frame(width: 140, height: 140)
                    // Pixel-measured center of the generated ivory clock face.
                    .position(x: 149, y: 230)
            }
            .rotationEffect(.degrees(bobbing ? 0.35 : -0.35), anchor: .top)
            .offset(y: bobbing ? -1.5 : 1.5)
            .animation(
                .easeInOut(duration: model.isRunning ? 1.8 : 2.8)
                    .repeatForever(autoreverses: true),
                value: bobbing
            )

            if model.showsCompletion {
                CelebrationSparkles()
                    .frame(width: 230, height: 92)
                    .position(x: 145, y: 55)
                    .transition(.scale.combined(with: .opacity))
            }

            WindowDragArea()
                .frame(width: 205, height: 72)
                .position(x: 145, y: 72)
                .help("드래그해서 위치 이동")

            VStack(spacing: 8) {
                FloatingIconButton(symbol: "gearshape.fill", label: "타이머 설정") {
                    model.toggleSettings()
                }
                FloatingIconButton(symbol: "arrow.counterclockwise", label: "초기화") {
                    model.resetCurrentSession()
                }
                FloatingIconButton(symbol: "xmark", label: "숨기기") {
                    onHide()
                }
            }
            .position(x: 296, y: 186)
        }
        .frame(width: 316, height: 440)
        .scaleEffect(displayScale)
        .frame(width: 316 * displayScale, height: 440 * displayScale)
        .onAppear {
            bobbing = true
            tailSwinging = true
        }
    }
}

struct TimerFaceView: View {
    @ObservedObject var model: TimerModel

    private var accent: Color {
        model.phase == .focus ? .pomodoroCoral : .pomodoroSage
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.72), lineWidth: 8)

            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: model.progress)

            VStack(spacing: 5) {
                Text(model.phase.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent))

                Text(model.formattedTime)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.pomodoroInk)
                    .minimumScaleFactor(0.75)

                Button(action: model.toggleRunning) {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.pomodoroInk)
                        .frame(width: 30, height: 27)
                        .background(Circle().fill(Color.pomodoroBlush))
                }
                .buttonStyle(.plain)
                .help(model.isRunning ? "일시정지" : "시작")
            }
        }
    }
}

struct EncouragementBubble: View {
    @ObservedObject var model: TimerModel
    let message: String
    let milestone: Int
    let pointsLeft: Bool

    var body: some View {
        BubbleCard(pointsLeft: pointsLeft) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(Color.pomodoroCoral)
                    Text("\(milestone)% 남았어")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.pomodoroCoral)
                    Spacer()
                    Button(action: model.dismissEncouragement) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.pomodoroInk.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }

                Text(message)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.pomodoroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .frame(width: 330, height: 180)
    }
}

struct SettingsBubble: View {
    @ObservedObject var model: TimerModel
    let pointsLeft: Bool

    var body: some View {
        BubbleCard(pointsLeft: pointsLeft) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("타이머 설정")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.pomodoroInk)
                    Spacer()
                    Button {
                        model.toggleSettings()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.pomodoroInk.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                DurationRow(
                    title: "집중",
                    minutes: model.focusMinutes,
                    onMinus: { model.adjustFocus(by: -5) },
                    onPlus: { model.adjustFocus(by: 5) }
                )

                DurationRow(
                    title: "휴식",
                    minutes: model.restMinutes,
                    onMinus: { model.adjustRest(by: -5) },
                    onPlus: { model.adjustRest(by: 5) }
                )

                HStack(spacing: 8) {
                    PresetButton(label: "25/5", selected: model.focusMinutes == 25 && model.restMinutes == 5) {
                        model.applyPreset(focus: 25, rest: 5)
                    }
                    PresetButton(label: "45/15", selected: model.focusMinutes == 45 && model.restMinutes == 15) {
                        model.applyPreset(focus: 45, rest: 15)
                    }
                    PresetButton(label: "60/15", selected: model.focusMinutes == 60 && model.restMinutes == 15) {
                        model.applyPreset(focus: 60, rest: 15)
                    }
                }

                PrimaryButton(title: "시작", color: .pomodoroCoral) {
                    model.startFocusSession()
                }
            }
        }
        .frame(width: 330, height: 330)
    }
}

struct CompletionBubble: View {
    @ObservedObject var model: TimerModel
    let pointsLeft: Bool

    private var completedFocus: Bool { model.phase == .focus }

    var body: some View {
        BubbleCard(pointsLeft: pointsLeft) {
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button(action: model.dismissCompletion) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.pomodoroInk.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                ZStack {
                    HStack(spacing: 28) {
                        ConfettiMark(rotation: -28)
                        ConfettiMark(rotation: 28)
                    }
                    Text(completedFocus ? "집중 완료!" : "휴식 완료!")
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundStyle(completedFocus ? Color.pomodoroCoral : Color.pomodoroSage)
                }

                Text(completedFocus ? "\(model.totalSeconds / 60)분 집중했어요" : "충전이 끝났어요")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.pomodoroInk)

                PrimaryButton(
                    title: completedFocus ? "\(model.restMinutes)분 휴식 시작" : "\(model.focusMinutes)분 집중 시작",
                    color: completedFocus ? .pomodoroCoral : .pomodoroSage
                ) {
                    if completedFocus {
                        model.startRestSession()
                    } else {
                        model.startFocusSession()
                    }
                }

                Button(completedFocus ? "5분 더" : "5분 더 쉬기") {
                    model.addFiveMinutes()
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pomodoroInk)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.pomodoroInk.opacity(0.09), lineWidth: 1)
                        )
                )
            }
        }
        .frame(width: 330, height: 310)
    }
}

struct DurationRow: View {
    let title: String
    let minutes: Int
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pomodoroInk)
                .frame(width: 30, alignment: .center)

            StepButton(symbol: "minus", action: onMinus)

            Text("\(minutes)분")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.pomodoroInk)
                .frame(maxWidth: .infinity)

            StepButton(symbol: "plus", action: onPlus)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color.white.opacity(0.42)))
    }
}

struct StepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.pomodoroInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.82)))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct PresetButton: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? Color.white : Color.pomodoroInk)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Capsule()
                    .fill(selected ? Color.pomodoroCoral : Color.white.opacity(0.52))
            )
    }
}

struct PrimaryButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 17).fill(color))
                .shadow(color: color.opacity(0.25), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct FloatingIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.pomodoroInk.opacity(0.78))
                .frame(width: 29, height: 29)
                .background(Circle().fill(Color.pomodoroIvory.opacity(0.94)))
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct BubbleCard<Content: View>: View {
    let pointsLeft: Bool
    @ViewBuilder let content: Content

    init(pointsLeft: Bool, @ViewBuilder content: () -> Content) {
        self.pointsLeft = pointsLeft
        self.content = content()
    }

    var body: some View {
        content
            .padding(23)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.pomodoroIvory.opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
            )
            .overlay(alignment: pointsLeft ? .leading : .trailing) {
                BubblePointer()
                    .fill(Color.pomodoroIvory.opacity(0.96))
                    .frame(width: 18, height: 28)
                    .rotationEffect(.degrees(pointsLeft ? 0 : 180))
                    .offset(x: pointsLeft ? -13 : 13)
            }
            .padding(.horizontal, 14)
    }
}

struct BubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ConfettiMark: View {
    let rotation: Double

    var body: some View {
        Capsule()
            .fill(Color.pomodoroCoral)
            .frame(width: 7, height: 22)
            .rotationEffect(.degrees(rotation))
    }
}

struct CelebrationSparkles: View {
    @State private var celebrating = false

    var body: some View {
        ZStack {
            sparkle(x: 22, y: 52, rotation: -55, color: .pomodoroCoral)
            sparkle(x: 48, y: 18, rotation: -22, color: .pomodoroSage)
            sparkle(x: 181, y: 19, rotation: 24, color: .pomodoroCoral)
            sparkle(x: 210, y: 54, rotation: 58, color: .pomodoroSage)
            Circle()
                .fill(Color.pomodoroBlush)
                .frame(width: 9, height: 9)
                .position(x: 15, y: 16)
            Circle()
                .fill(Color.pomodoroBlush)
                .frame(width: 8, height: 8)
                .position(x: 220, y: 15)
        }
        .scaleEffect(celebrating ? 1.05 : 0.9)
        .opacity(celebrating ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: celebrating)
        .onAppear { celebrating = true }
        .allowsHitTesting(false)
    }

    private func sparkle(x: CGFloat, y: CGFloat, rotation: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 7, height: 22)
            .rotationEffect(.degrees(rotation))
            .position(x: x, y: y)
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggingView {
        DraggingView()
    }

    func updateNSView(_ nsView: DraggingView, context: Context) {}
}

final class DraggingView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

extension Color {
    static let pomodoroCoral = Color(red: 1.0, green: 0.31, blue: 0.29)
    static let pomodoroSage = Color(red: 0.35, green: 0.62, blue: 0.43)
    static let pomodoroIvory = Color(red: 1.0, green: 0.96, blue: 0.90)
    static let pomodoroBlush = Color(red: 1.0, green: 0.78, blue: 0.71)
    static let pomodoroInk = Color(red: 0.20, green: 0.14, blue: 0.11)
}

private enum PetAssets {
    static let catTimerBody = load("cat_timer_body")
    static let catTail = load("cat_tail")

    private static func load(_ name: String) -> NSImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(size: NSSize(width: 280, height: 420))
    }
}
