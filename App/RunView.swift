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
                QuizView(title: run.title, session: $session)
            case .completed(let stars):
                ResultView(title: run.title, session: session, stars: stars, isDaily: isDaily,
                           nextStop: nextStop, retry: retry, next: playNext, close: { presented = nil })
                    .onAppear { record(stars: stars) }
            case .outOfFuel:
                ResultView(title: run.title, session: session, stars: nil, isDaily: isDaily,
                           nextStop: nil, retry: retry, next: {}, close: { presented = nil })
                    .onAppear { model.play(.hint) }
            }
        }
    }

    private var isDaily: Bool {
        if case .daily = run.kind { true } else { false }
    }

    private var nextStop: Stop? {
        guard case .stop(let stop) = run.kind, let chapter = Adventure.chapter(for: stop.continent) else { return nil }
        guard stop.number < chapter.stops.count else { return nil }
        return chapter.stops[stop.number]
    }

    private func record(stars: Int) {
        guard !recorded else { return }
        recorded = true
        switch run.kind {
        case .stop(let stop): model.finish(stop: stop, stars: stars)
        case .daily: model.finishDaily(score: session.score)
        }
        model.play(stars == 3 ? .milestone : .solve)
    }

    private func retry() {
        session = run.makeSession()
        recorded = false
    }

    private func playNext() {
        guard let stop = nextStop else { return }
        run = Run(kind: .stop(stop))
        session = run.makeSession()
        recorded = false
    }
}

private struct QuizView: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var session: QuizSession

    @State private var displayed: Question?
    @State private var lastResult: QuizSession.AnswerResult?
    @State private var locked = false

    var body: some View {
        VStack(spacing: 20) {
            header
            ProgressView(value: session.progress).tint(Theme.star)
            Spacer(minLength: 0)
            if let question = displayed ?? session.currentQuestion {
                Text(FlagCatalog.emoji(iso2: question.answer))
                    .font(.system(size: 130))
                    .accessibilityLabel("A national flag")
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
    }

    private var header: some View {
        HStack {
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

        Task {
            try? await Task.sleep(for: .milliseconds(result.isCorrect ? 650 : 1100))
            lastResult = nil
            displayed = session.currentQuestion
            locked = false
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

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(stars == nil ? "Out of fuel" : "Stop complete!").font(.largeTitle.bold()).foregroundStyle(.white)
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
            Spacer()
            VStack(spacing: 12) {
                if stars != nil, let nextStop, !isDaily {
                    primary("Next: Stop \(nextStop.number)", action: next)
                }
                if !isDaily { secondary(stars == nil ? "Try again" : "Play again", action: retry) }
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
