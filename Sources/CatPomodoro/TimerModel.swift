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
            case .focus: return "Focus"
            case .rest: return "Break"
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
    @Published private(set) var showsGoalPrompt = false
    @Published private(set) var showsGoalHover = false
    @Published var focusGoalDraft = ""
    @Published private(set) var currentFocusGoal: String?
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
    static let maximumGoalLength = 80
    private static let encouragements: [Int: [String]] = [
        75: [
            "Great start! You’re already doing wonderfully, meow!",
            "The first step is the hardest—and you nailed it, meow!",
            "Focus mode is on! Keep this lovely rhythm going, meow!",
            "You’re off to a great start. I’m cheering right beside you!",
            "Your pace is purr-fect. Slow and steady, meow!"
        ],
        50: [
            "Halfway there already! Keep that momentum going, meow!",
            "Halfway done! Your focus is shining bright.",
            "You did half of it! I’ll stay for the rest, meow!",
            "Look how far you’ve come. Let’s keep going!",
            "Midpoint reached! Stretch once, then focus, meow!"
        ],
        25: [
            "Almost there! Just one more little push, meow!",
            "The finish line is in sight. Keep going!",
            "Just a little more. Your break is waiting, tail wagging!",
            "You’ve come this far—you’ve practically got it, meow!",
            "Amazing focus! Let’s tiptoe to the finish."
        ],
        10: [
            "Just a tiny bit more! A cozy break is almost here.",
            "Final 10%! I’m right beside you to the end, meow!",
            "Your break is so close! One last burst of focus!",
            "Almost done! Wrap up what you’re working on, meow.",
            "A little more, then snack—oops, break time, meow!"
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
        showsSettings
            || showsCompletion
            || showsGoalPrompt
            || showsGoalHover
            || encouragementMessage != nil
    }

    var isShowingEncouragement: Bool {
        encouragementMessage != nil
            && !showsSettings
            && !showsCompletion
            && !showsGoalPrompt
    }

    var isShowingCompactBubble: Bool {
        isShowingEncouragement || showsGoalHover
    }

    var canConfirmFocusGoal: Bool {
        !focusGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleRunning() {
        if isRunning {
            pause()
        } else {
            if remainingSeconds == 0 {
                resetCurrentSession()
            }

            if phase == .focus, currentFocusGoal == nil {
                startFocusSession()
                return
            }

            startTicker()
        }
    }

    func startFocusSession() {
        stopTicker()
        triggeredMilestones.removeAll()
        phase = .focus
        totalSeconds = focusMinutes * 60
        remainingSeconds = totalSeconds
        isRunning = false
        currentFocusGoal = nil
        clearEncouragement()
        showsGoalHover = false
        showsCompletion = false
        showsSettings = false
        showsGoalPrompt = true
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    func confirmFocusGoal() {
        let goal = focusGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }

        currentFocusGoal = String(goal.prefix(Self.maximumGoalLength))
        focusGoalDraft = ""
        start(phase: .focus, minutes: focusMinutes)
    }

    func updateFocusGoalDraft(_ value: String) {
        focusGoalDraft = String(value.prefix(Self.maximumGoalLength))
    }

    func backToTimerSettings() {
        showsGoalPrompt = false
        showsGoalHover = false
        showsCompletion = false
        showsSettings = true
        onPresentationChanged?()
    }

    func dismissGoalPrompt() {
        showsGoalPrompt = false
        focusGoalDraft = ""
        onPresentationChanged?()
    }

    func startRestSession() {
        currentFocusGoal = nil
        focusGoalDraft = ""
        showsGoalHover = false
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
        currentFocusGoal = nil
        focusGoalDraft = ""
        closePresentations()
        onTimerStateChanged?()
    }

    func openSettings() {
        clearEncouragement()
        showsGoalHover = false
        showsGoalPrompt = false
        showsCompletion = false
        showsSettings = true
        onPresentationChanged?()
    }

    func toggleSettings() {
        if !showsSettings {
            clearEncouragement()
        }
        showsGoalHover = false
        showsGoalPrompt = false
        showsCompletion = false
        showsSettings.toggle()
        onPresentationChanged?()
    }

    func dismissCompletion() {
        showsCompletion = false
        triggeredMilestones.removeAll()
        remainingSeconds = duration(for: phase) * 60
        totalSeconds = remainingSeconds
        if phase == .focus {
            currentFocusGoal = nil
            focusGoalDraft = ""
        }
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
        showsGoalPrompt = false
        showsGoalHover = false
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
        showsGoalPrompt = false
        showsGoalHover = false
        showsCompletion = false
        showEncouragement(for: 75)
    }

    func previewGoalPrompt() {
        stopTicker()
        clearEncouragement()
        phase = .focus
        totalSeconds = focusMinutes * 60
        remainingSeconds = totalSeconds
        isRunning = false
        currentFocusGoal = nil
        focusGoalDraft = ""
        showsSettings = false
        showsCompletion = false
        showsGoalHover = false
        showsGoalPrompt = true
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    func previewGoalHover() {
        stopTicker()
        clearEncouragement()
        phase = .focus
        totalSeconds = focusMinutes * 60
        remainingSeconds = max(totalSeconds - (7 * 60 + 12), 1)
        isRunning = true
        currentFocusGoal = "Finish the landing page wireframe"
        focusGoalDraft = ""
        showsSettings = false
        showsCompletion = false
        showsGoalPrompt = false
        showsGoalHover = true
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    func setGoalHoverVisible(_ visible: Bool) {
        let shouldShow = visible
            && isRunning
            && phase == .focus
            && currentFocusGoal != nil
            && !showsSettings
            && !showsCompletion
            && !showsGoalPrompt
            && encouragementMessage == nil

        guard showsGoalHover != shouldShow else { return }
        showsGoalHover = shouldShow
        onPresentationChanged?()
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
        if showsGoalHover {
            showsGoalHover = false
            onPresentationChanged?()
        }
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
        showsGoalPrompt = false
        showsGoalHover = false
        showsCompletion = true

        NSSound(named: NSSound.Name("Glass"))?.play()
        deliverCompletionNotification()
        onPresentationChanged?()
        onTimerStateChanged?()
    }

    private func deliverCompletionNotification() {
        let content = UNMutableNotificationContent()
        if phase == .focus {
            content.title = "Focus Complete!"
            content.body = "You focused for \(totalSeconds / 60) minutes. Ready for a short break?"
        } else {
            content.title = "Break Complete!"
            content.body = "You’re recharged. Time to focus again."
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
        showsGoalPrompt = false
        showsGoalHover = false
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
              !showsGoalPrompt,
              let message = Self.encouragements[milestone]?.randomElement() else { return }

        encouragementDismissTask?.cancel()
        showsGoalHover = false
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
