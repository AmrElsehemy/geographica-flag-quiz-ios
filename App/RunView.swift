import FlagQuizCore
import GameTimeExperience
import GeographicaCore
import GeographicaFlags
import SwiftUI

/// Plays a run end to end: questions, then the result screen. Owns retry and "next stop".
struct RunView: View {
    @Environment(AppModel.self) private var model
    let initialRun: Run
    @Binding var presented: Run?

    @State private var run: Run
    @State private var session: QuizSession
    @State private var recorded = false
    @State private var attemptID = UUID().uuidString
    @State private var refueling = false
    @State private var refuelMessage: String?
    @State private var tracker: RunAnalytics?
    @State private var starsHintShown = false

    init(run: Run, presented: Binding<Run?>) {
        self.initialRun = run
        self._presented = presented
        self._run = State(initialValue: run)
        self._session = State(initialValue: run.makeSession())
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch session.state {
            case .inProgress:
                QuizView(title: run.title, session: $session,
                         onQuestionShown: { track { $0.questionShown() } },
                         onAnswered: { result in track { $0.answered(result, session: session) } },
                         onQuit: quit)
            case .completed(let stars):
                ResultView(title: run.title, session: session, stars: stars, isDaily: isDaily,
                           nextStop: nextStop, retry: retry, next: playNext, close: close,
                           note: dailyNote ?? (starsHintShown ? Hint.stars.message : nil),
                           onLeaderboard: isDaily && model.gameCenter.isAuthenticated
                               ? { model.gameCenter.showLeaderboard() } : nil)
                    .onAppear { record(stars: stars) }
            case .outOfFuel:
                ResultView(title: run.title, session: session, stars: nil, isDaily: isDaily,
                           nextStop: nil, retry: retry, next: {}, close: close,
                           note: dailyNote,
                           canRefuel: offersRefuel, refueling: refueling, refuelMessage: refuelMessage,
                           refuel: watchAdToRefuel)
                    .onAppear {
                        model.play(.hint)
                        if offersRefuel { track { $0.refuelOffered(session: session) } }
                        // A daily attempt is used up once it can't be continued.
                        if !offersRefuel { record(stars: nil) }
                    }
            }
        }
        .onAppear { if tracker == nil { beginAttempt() } }
    }

    // MARK: Analytics

    private func beginAttempt() {
        attemptID = UUID().uuidString
        let context: RunContext
        switch run.kind {
        case .stop(let stop): context = .adventure(stop: stop, session: session, attemptID: attemptID)
        case .daily(let counts): context = .daily(counts: counts, session: session, attemptID: attemptID)
        case .tutorial: return   // the tutorial has its own view and funnel
        }
        starsHintShown = false
        var started = model.analytics.makeRun(context)
        started.start()
        tracker = started
    }

    private func track(_ update: (inout RunAnalytics) -> Void) {
        guard var current = tracker else { return }
        update(&current)
        tracker = current
    }

    private func quit() {
        track { $0.abandoned(session: session) }
        presented = nil
    }

    private var isDaily: Bool {
        if case .daily = run.kind { true } else { false }
    }

    private var nextStop: Stop? {
        guard case .stop(let stop) = run.kind, let chapter = Adventure.chapter(for: stop.continent) else { return nil }
        guard stop.number < chapter.stops.count else { return nil }
        return chapter.stops[stop.number]
    }

    private var dailyNote: String? {
        guard case .daily(let counts) = run.kind else { return nil }
        guard counts else { return "Practice round. Your daily score and streak aren't affected." }
        var lines = ["Counts toward today's score and your streak."]
        if let leaderboard = leaderboardNote { lines.append(leaderboard) }
        return lines.joined(separator: "\n")
    }

    private var leaderboardNote: String? {
        switch model.dailyLeaderboardStatus {
        case .submitted:
            return "Score added to today's leaderboard."
        case .queued:
            return model.gameCenter.isAuthenticated
                ? "Score saved. It will reach the leaderboard shortly."
                : "Sign in to Game Center to join the leaderboard."
        case .nothingToSubmit, nil:
            return nil
        }
    }

    /// Records the result once. `stars` is nil when the run ended out of fuel.
    private func record(stars: Int?) {
        // The tracker sends each terminal event at most once, so this is safe to call repeatedly.
        if let stars {
            track { $0.completed(stars: stars, session: session) }
        } else {
            track { $0.failed(session: session) }
        }
        guard !recorded else { return }
        switch run.kind {
        case .stop(let stop):
            guard let stars else { return }   // a failed stop earns nothing
            recorded = true
            model.finish(stop: stop, stars: stars)
            if !model.onboarding.hasSeen(.stars) {
                starsHintShown = true
                model.markHintSeen(.stars)
            }
        case .daily(let counts):
            recorded = true
            if counts {
                model.finishDaily(score: session.score, on: run.startedAt)
                tracker?.dailyCompleted(score: session.score, streak: model.progress.dailyStreak)
            }
        case .tutorial:
            return
        }
        if let stars { model.play(stars == 3 ? .milestone : .solve) }
    }

    /// The out-of-fuel screen offers an ad only if this attempt can still be refuelled and ads exist.
    private var offersRefuel: Bool { session.canRefuel && model.refuelOfferAvailable }

    private func close() {
        if session.state == .outOfFuel {
            track { $0.refuelDeclined(session: session) }
            record(stars: nil)
        }
        presented = nil
    }

    private func retry() {
        if session.state == .outOfFuel {
            track { $0.refuelDeclined(session: session) }
            record(stars: nil)
        }
        if case .daily = run.kind { run = Run(kind: .daily(counts: false)) }
        session = run.makeSession()
        recorded = false
        refuelMessage = nil
        beginAttempt()
    }

    private func watchAdToRefuel() {
        guard !refueling, session.canRefuel else { return }
        refueling = true
        refuelMessage = nil
        track { $0.refuelAccepted(session: session) }
        Task { @MainActor in
            let outcome = await model.requestRefuel(attemptID: attemptID, refuelNumber: session.refuelsUsed + 1)
            refueling = false
            track { $0.refuelResolved(outcome, session: session) }
            switch outcome {
            case .refueled:
                session.refuel()
                model.play(.hint)
            case .cancelled:
                refuelMessage = "Watch the whole ad to earn the extra fuel."
            case .unavailable:
                refuelMessage = "No ad is ready right now. Try again in a moment."
            case .ineligible:
                refuelMessage = "Ads aren't available right now. You can try again instead."
            }
        }
    }

    private func playNext() {
        guard let stop = nextStop else { return }
        run = Run(kind: .stop(stop))
        session = run.makeSession()
        recorded = false
        refuelMessage = nil
        beginAttempt()
    }
}

private struct QuizView: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var session: QuizSession
    let onQuestionShown: () -> Void
    let onAnswered: (QuizSession.AnswerResult) -> Void
    let onQuit: () -> Void
    /// Optional coaching line per question index (used by the tutorial).
    var coachLines: [String] = []
    /// Shows a text button (e.g. "Skip") instead of the close icon.
    var quitTitle: String?

    @State private var displayed: Question?
    @State private var lastResult: QuizSession.AnswerResult?
    @State private var locked = false

    var body: some View {
        VStack(spacing: 20) {
            header
            ProgressView(value: session.progress).tint(Theme.star)
            if let coach {
                Text(coach)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .id(coach)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            if let question = displayed ?? session.currentQuestion {
                FlagView(iso2: question.answer, accessibilityLabel: "A national flag")
                    .frame(maxWidth: 300, maxHeight: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                    .id(question.id)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                Text("Which country is this?").font(.title3).foregroundStyle(.white.opacity(0.85))
                VStack(spacing: 12) {
                    ForEach(question.choices, id: \.self) { code in
                        ChoiceButton(name: CountryCatalog.country(iso2: code)?.name ?? code,
                                     style: style(for: code, in: question)) { choose(code) }
                            .allowsHitTesting(!locked)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .animation(.spring(duration: 0.35), value: displayed)
        .onAppear(perform: onQuestionShown)
    }

    /// The coaching line for the question currently on screen.
    private var coach: String? {
        guard let question = displayed ?? session.currentQuestion,
              let index = session.questions.firstIndex(of: question),
              coachLines.indices.contains(index) else { return nil }
        return coachLines[index]
    }

    private var header: some View {
        HStack {
            Button(action: onQuit) {
                if let quitTitle {
                    Text(quitTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                }
            }
            .accessibilityLabel(quitTitle ?? "Quit")
            Text(title).font(.headline).foregroundStyle(.white)
            Spacer()
            if session.streak > 1 {
                Label("\(session.streak)", systemImage: "flame.fill").foregroundStyle(.orange)
            }
            HStack(spacing: 2) {
                ForEach(0..<QuizSession.startingFuel, id: \.self) { index in
                    Image(systemName: index < session.fuel ? "fuelpump.fill" : "fuelpump")
                        .foregroundStyle(index < session.fuel ? Theme.star : .white.opacity(0.3))
                }
            }
            .accessibilityLabel("\(session.fuel) fuel left")
            Text("\(session.score)").font(.headline.monospacedDigit()).foregroundStyle(.white)
        }
    }

    private func style(for code: String, in question: Question) -> ChoiceButton.Style {
        guard let result = lastResult, result.question == question else { return .normal }
        if code == question.answer { return .correct }
        if code == result.selected { return .wrong }
        return .dimmed
    }

    private func choose(_ code: String) {
        guard !locked, let question = session.currentQuestion else { return }
        displayed = question
        locked = true
        guard let result = session.answer(code) else { return }
        lastResult = result
        model.play(result.isCorrect ? .placement : .invalidMove)
        onAnswered(result)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(result.isCorrect ? 650 : 1100))
            lastResult = nil
            displayed = session.currentQuestion
            locked = false
            if displayed != nil { onQuestionShown() }
        }
    }
}

private struct ChoiceButton: View {
    enum Style { case normal, correct, wrong, dimmed }

    let name: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(style == .dimmed ? .white.opacity(0.4) : .white)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch style {
        case .normal: Theme.accent
        case .correct: Theme.good
        case .wrong: Theme.bad
        case .dimmed: Color.white.opacity(0.1)
        }
    }
}

private struct ResultView: View {
    let title: String
    let session: QuizSession
    let stars: Int?
    let isDaily: Bool
    let nextStop: Stop?
    let retry: () -> Void
    let next: () -> Void
    let close: () -> Void
    var note: String?
    /// Shows a "View leaderboard" button when set (daily runs, signed in to Game Center).
    var onLeaderboard: (() -> Void)?
    var canRefuel = false
    var refueling = false
    var refuelMessage: String?
    var refuel: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(stars == nil ? "Out of fuel" : (isDaily ? "Daily complete!" : "Stop complete!")).font(.largeTitle.bold()).foregroundStyle(.white)
            Text(title).foregroundStyle(.white.opacity(0.8))
            if let stars {
                HStack {
                    ForEach(0..<Adventure.maxStarsPerStop, id: \.self) { index in
                        Image(systemName: index < stars ? "star.fill" : "star")
                            .font(.system(size: 44))
                            .foregroundStyle(index < stars ? Theme.star : .white.opacity(0.3))
                    }
                }
                .accessibilityLabel("\(stars) of 3 stars")
            } else {
                Text("Three wrong answers ends the trip. Have another go!").multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
            }
            VStack(spacing: 4) {
                Text("\(session.score) points").font(.title2.monospacedDigit()).foregroundStyle(.white)
                Text("\(session.correctCount)/\(session.questions.count) correct · best streak \(session.bestStreak)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            if let note {
                Text(note).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            VStack(spacing: 12) {
                if stars == nil, canRefuel {
                    primary(refueling ? "Loading ad…" : "Watch an ad to keep going", action: refuel)
                        .disabled(refueling)
                }
                if let refuelMessage {
                    Text(refuelMessage).font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                }
                if stars != nil, let nextStop, !isDaily {
                    primary("Next: Stop \(nextStop.number)", action: next)
                }
                if let onLeaderboard { secondary("View leaderboard", action: onLeaderboard) }
                secondary(isDaily ? "Practice again" : (stars == nil ? "Try again" : "Play again"), action: retry)
                secondary("Back to map", action: close)
            }
        }
        .padding(24)
    }

    private func primary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.black).background(Theme.star, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func secondary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white).background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// The first-run practice round: three guided flags, wrong answers are free, and it can be skipped.
struct TutorialView: View {
    @Environment(AppModel.self) private var model
    let replay: Bool
    @Binding var presented: Run?

    @State private var session = Tutorial.session()
    @State private var tracker: TutorialAnalytics?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if case .completed = session.state {
                completion
            } else {
                QuizView(title: "How to play", session: $session,
                         onQuestionShown: {},
                         onAnswered: { result in track { $0.step(index: session.currentIndex - 1, correct: result.isCorrect) } },
                         onQuit: skip,
                         coachLines: Tutorial.steps.map(\.coach),
                         quitTitle: "Skip")
            }
        }
        .onAppear {
            guard tracker == nil else { return }
            var started = model.analytics.makeTutorial(replay: replay)
            started.start()
            tracker = started
        }
    }

    private var completion: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("You're ready!").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Travel the world one continent at a time. Earn stars to unlock new stops, and watch your fuel.")
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button(action: finish) {
                Text(replay ? "Back to the map" : "Start adventure").font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.black).background(Theme.star, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
        .onAppear {
            track { $0.completed(session: session) }
            model.play(.solve)
        }
    }

    private func track(_ update: (inout TutorialAnalytics) -> Void) {
        guard var current = tracker else { return }
        update(&current)
        tracker = current
    }

    private func skip() {
        track { $0.skipped(atStep: session.currentIndex) }
        if !replay { model.skipTutorial() }
        presented = nil
    }

    /// Completion is recorded on the button, not when the screen appears, so the ad-consent form
    /// (which waits for the tutorial to be done) can't pop up over "You're ready!".
    private func finish() {
        model.completeTutorial()
        presented = nil
    }
}
