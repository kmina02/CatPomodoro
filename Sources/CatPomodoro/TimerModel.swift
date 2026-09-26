import AppKit
import Foundation
import UserNotifications

@MainActor
final class TimerModel: ObservableObject {
    enum Phase: String, Codable {
        case focus
        case rest

        var title: String {
            switch self {
            case .focus: return "집중"
            case .rest: return "휴식"
            }
        }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var totalSeconds: Int
    @Published private(set) var isRunning = false
    @Published var focusMinutes: Int
    @Published var restMinutes: Int
    @Published private(set) var showsSettings = false
    @Published private(set) var showsCompletion = false
    @Published private(set) var encouragementMessage: String?
    @Published private(set) var encouragementMilestone: Int?
    @Published var bubbleOnLeft = false

    var onPresentationChanged: (() -> Void)?
    var onTimerStateChanged: (() -> Void)?

    private var ticker: Timer?
    private var targetDate: Date?
    private var encouragementDismissTask: Task<Void, Never>?
    private var triggeredMilestones = Set<Int>()

    private let milestonePercents = [75, 50, 25, 10]
    private static let encouragements: [Int: [String]] = [
        75: [
            "시작이 반이라더니, 벌써 멋지게 출발했다냥!",
            "첫발이 제일 어려운 법! 지금 아주 잘하고 있다냥.",
            "집중 모드가 반짝 켜졌네! 이 흐름 그대로 가보자, 야옹!",
            "좋은 출발이야. 내가 옆에서 응원하고 있다냥!",
            "지금 페이스 딱 좋아! 천천히 꾸준히 가보자냥."
        ],
        50: [
            "벌써 반이나 왔다냥! 이 기세 그대로 가보자!",
            "절반 통과! 집중력이 아주 반짝반짝한다냥.",
            "반이나 해냈어! 남은 절반도 내가 같이 있어줄게, 야옹!",
            "여기까지 온 거 정말 대단해. 한 번 더 쭉 가자냥!",
            "반환점 도착! 어깨 한 번 펴고 다시 집중, 야옹!"
        ],
        25: [
            "거의 다 왔다냥! 마지막 한 걸음만 더!",
            "끝이 보인다! 지금처럼만 하면 된다냥.",
            "조금만 더 힘내자. 휴식이 꼬리를 흔들며 기다린다냥!",
            "여기까지 왔으면 다 한 거나 마찬가지야. 야옹!",
            "집중력 최고! 마무리까지 살금살금 가보자냥."
        ],
        10: [
            "진짜 조금만 더! 곧 포근한 휴식이다냥.",
            "마지막 10%! 내가 끝까지 옆에 있을게, 야옹!",
            "휴식이 코앞이다냥! 한 번만 더 집중!",
            "거의 끝! 지금 하던 것만 마무리해보자냥.",
            "조금만 더 하면 간식… 아니, 휴식 시간이다냥!"
        ]
    ]

    init() {
        let defaults = UserDefaults.standard
        let savedFocus = defaults.integer(forKey: "focusMinutes")
        let savedRest = defaults.integer(forKey: "restMinutes")
        focusMinutes = savedFocus > 0 ? savedFocus : 45
        restMinutes = savedRest > 0 ? savedRest : 15
        remainingSeconds = (savedFocus > 0 ? savedFocus : 45) * 60
        totalSeconds = (savedFocus > 0 ? savedFocus : 45) * 60
    }

    var formattedTime: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }

    var isPresentingBubble: Bool {
        showsSettings || showsCompletion || encouragementMessage != nil
    }

    var isShowingEncouragement: Bool {
        encouragementMessage != nil && !showsSettings && !showsCompletion
    }

    func toggleRunning() {
        if isRunning {
            pause()
        } else {
            if remainingSeconds == 0 {
                resetCurrentSession()
            }
            startTicker()
        }
    }

    func startFocusSession() {
        start(phase: .focus, minutes: focusMinutes)
    }

    func startRestSession() {
        start(phase: .rest, minutes: restMinutes)
    }

    func addFiveMinutes() {
        start(phase: phase, minutes: 5)
    }

    func resetCurrentSession() {
        stopTicker()
        triggeredMilestones.removeAll()
        remainingSeconds = duration(for: phase) * 60
        totalSeconds = remainingSeconds
        isRunning = false
        closePresentations()
        onTimerStateChanged?()
    }

    func openSettings() {
        clearEncouragement()
        showsCompletion = false
        showsSettings = true
        onPresentationChanged?()
    }

    func toggleSettings() {
        if !showsSettings {
            clearEncouragement()
        }
        showsCompletion = false
        showsSettings.toggle()
        onPresentationChanged?()
    }

    func dismissCompletion() {
        showsCompletion = false
        triggeredMilestones.removeAll()
        remainingSeconds = duration(for: phase) * 60
        totalSeconds = remainingSeconds
        onPresentationChanged?()
    }

    func previewCompletion() {
        stopTicker()
        clearEncouragement()
        triggeredMilestones.removeAll()
        phase = .focus
        totalSeconds = focusMinutes * 60
        remainingSeconds = 0
        isRunning = false
        showsSettings = false
        showsCompletion = true
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    func previewEncouragement() {
        stopTicker()
        phase = .focus
        totalSeconds = max(focusMinutes, 5) * 60
        remainingSeconds = Int(Double(totalSeconds) * 0.75)
        isRunning = false
        showsSettings = false
        showsCompletion = false
        showEncouragement(for: 75)
    }

    func dismissEncouragement() {
        guard encouragementMessage != nil else { return }
        clearEncouragement()
        onPresentationChanged?()
    }

    func adjustFocus(by delta: Int) {
        focusMinutes = min(max(focusMinutes + delta, 5), 180)
        persistDurations()
        refreshIdleDurationIfNeeded(for: .focus)
    }

    func adjustRest(by delta: Int) {
        restMinutes = min(max(restMinutes + delta, 5), 60)
        persistDurations()
        refreshIdleDurationIfNeeded(for: .rest)
    }

    func applyPreset(focus: Int, rest: Int) {
        focusMinutes = focus
        restMinutes = rest
        persistDurations()
        refreshIdleDurationIfNeeded(for: phase)
    }

    private func start(phase: Phase, minutes: Int) {
        stopTicker()
        triggeredMilestones.removeAll()
        self.phase = phase
        totalSeconds = max(minutes, 1) * 60
        remainingSeconds = totalSeconds
        closePresentations()
        startTicker()
    }

    private func startTicker() {
        guard remainingSeconds > 0 else { return }
        isRunning = true
        targetDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        ticker?.invalidate()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        onTimerStateChanged?()
    }

    private func pause() {
        updateRemainingTime()
        stopTicker()
        isRunning = false
        onTimerStateChanged?()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        targetDate = nil
    }

    private func tick() {
        updateRemainingTime()
        if remainingSeconds <= 0 {
            completeCurrentSession()
        }
    }

    private func updateRemainingTime() {
        guard let targetDate else { return }
        let previousSeconds = remainingSeconds
        let updatedSeconds = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
        remainingSeconds = updatedSeconds
        checkEncouragementMilestones(from: previousSeconds, to: updatedSeconds)
    }

    private func completeCurrentSession() {
        stopTicker()
        clearEncouragement()
        remainingSeconds = 0
        isRunning = false
        showsSettings = false
        showsCompletion = true

        NSSound(named: NSSound.Name("Glass"))?.play()
        deliverCompletionNotification()
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    private func deliverCompletionNotification() {
        let content = UNMutableNotificationContent()
        if phase == .focus {
            content.title = "집중 완료!"
            content.body = "\(totalSeconds / 60)분 집중했어요. 이제 잠깐 쉬어볼까요?"
        } else {
            content.title = "휴식 완료!"
            content.body = "충전 완료. 다시 집중을 시작할 시간이에요."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "cat-pomodoro-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func closePresentations() {
        let wasPresenting = isPresentingBubble
        clearEncouragement()
        showsSettings = false
        showsCompletion = false
        if wasPresenting {
            onPresentationChanged?()
        }
    }

    private func refreshIdleDurationIfNeeded(for changedPhase: Phase) {
        guard !isRunning, !showsCompletion, phase == changedPhase else { return }
        remainingSeconds = duration(for: phase) * 60
        totalSeconds = remainingSeconds
    }

    private func duration(for phase: Phase) -> Int {
        phase == .focus ? focusMinutes : restMinutes
    }

    private func checkEncouragementMilestones(from previousSeconds: Int, to currentSeconds: Int) {
        guard phase == .focus, totalSeconds > 0, previousSeconds > currentSeconds else { return }

        let previousRatio = Double(previousSeconds) / Double(totalSeconds)
        let currentRatio = Double(currentSeconds) / Double(totalSeconds)
        let crossed = milestonePercents.filter { milestone in
            let threshold = Double(milestone) / 100.0
            return !triggeredMilestones.contains(milestone)
                && previousRatio > threshold
                && currentRatio <= threshold
        }

        guard let milestone = crossed.last else { return }
        crossed.forEach { triggeredMilestones.insert($0) }
        showEncouragement(for: milestone)
    }

    private func showEncouragement(for milestone: Int) {
        guard !showsSettings,
              !showsCompletion,
              let message = Self.encouragements[milestone]?.randomElement() else { return }

        encouragementDismissTask?.cancel()
        encouragementMilestone = milestone
        encouragementMessage = message
        onPresentationChanged?()

        encouragementDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 6_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissEncouragement()
        }
    }

    private func clearEncouragement() {
        encouragementDismissTask?.cancel()
        encouragementDismissTask = nil
        encouragementMessage = nil
        encouragementMilestone = nil
    }

    private func persistDurations() {
        UserDefaults.standard.set(focusMinutes, forKey: "focusMinutes")
        UserDefaults.standard.set(restMinutes, forKey: "restMinutes")
    }
}
