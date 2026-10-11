import FlagQuizCore
import GeographicaCore
import SwiftUI

/// A quiz run presented full-screen: one stop or the daily challenge.
struct Run: Identifiable {
    enum Kind {
        case stop(Stop)
        /// `counts` is true for the first daily attempt of a UTC day; later ones are practice.
        case daily(counts: Bool)
        /// The first-run practice round. `replay` is true when opened from the settings menu.
        case tutorial(replay: Bool)
    }

    let id = UUID()
    let kind: Kind
    /// Fixed at launch so a run that crosses midnight UTC still belongs to the day it started on.
    let startedAt = Date()
    /// A ready-made session to play instead of building one (debug demo mode only).
    var preset: QuizSession?

    var title: String {
        switch kind {
        case .stop(let stop): "\(stop.continent.displayName) · Stop \(stop.number)"
        case .daily(let counts): counts ? "Daily Challenge" : "Daily Practice"
        case .tutorial: "How to play"
        }
    }

    func makeSession() -> QuizSession {
        if let preset { return preset }
        return switch kind {
        case .stop(let stop): Adventure.session(for: stop)
        case .daily: DailyChallenge.session(for: startedAt)
        case .tutorial: Tutorial.session()
        }
    }
}

struct WorldMapView: View {
    @Environment(AppModel.self) private var model
    @State private var run: Run?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let hint = model.onboarding.mapHint(progress: model.progress) {
                        HintCard(hint: hint) { model.markHintSeen(hint) }
                    }
                    dailyCard
                    ForEach(Adventure.chapters) { chapter in
                        ChapterCard(chapter: chapter, run: $run)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            // First launch goes straight into the tutorial, so hold the ad-consent form until it's done.
            .task(id: model.onboarding.shouldShowTutorial) {
                if !model.onboarding.shouldShowTutorial { await model.prepareAds() }
            }
            .onAppear {
                if let demo = model.consumeDemoRun() {
                    run = demo
                    return
                }
                if model.onboarding.shouldShowTutorial, run == nil { run = Run(kind: .tutorial(replay: false)) }
            }
            .navigationTitle("Flag Trek")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("How to play") { run = Run(kind: .tutorial(replay: true)) }
                        Toggle("Sound", isOn: Binding(get: { model.soundEnabled }, set: { model.setSoundEnabled($0) }))
                        Toggle("Haptics", isOn: Binding(get: { model.hapticsEnabled }, set: { model.setHapticsEnabled($0) }))
                        if model.ads.privacyOptionsRequired {
                            Button("Privacy options") { Task { @MainActor in await model.ads.presentPrivacyOptions() } }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Label("\(model.progress.totalStars)", systemImage: "star.fill")
                        .foregroundStyle(Theme.star)
                        .accessibilityLabel("\(model.progress.totalStars) stars earned")
                }
            }
        }
        .fullScreenCover(item: $run) { current in
            if case .tutorial(let replay) = current.kind {
                TutorialView(replay: replay, presented: $run)
            } else {
                RunView(run: current, presented: $run)
            }
        }
    }

    private var dailyCard: some View {
        let todayScore = model.progress.dailyScore(on: Date())
        return Button {
            model.markHintSeen(.daily)
            run = Run(kind: .daily(counts: todayScore == nil))
        } label: {
            HStack(spacing: 14) {
                Text("🌍").font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Challenge").font(.headline)
                    Text(todayScore.map { "Today: \($0) pts · tap to practice" } ?? "10 flags, the same for everyone today")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.progress.dailyStreak > 0 {
                    Label("\(model.progress.dailyStreak)", systemImage: "flame.fill").foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

private struct ChapterCard: View {
    @Environment(AppModel.self) private var model
    let chapter: Chapter
    @Binding var run: Run?

    var body: some View {
        let unlocked = model.progress.isChapterUnlocked(chapter)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chapter.continent.displayName).font(.title3.bold())
                Spacer()
                if unlocked {
                    Text("\(model.progress.stars(in: chapter))/\(chapter.maxStars) ★").foregroundStyle(Theme.star)
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
            if unlocked {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(chapter.stops) { stop in
                        StopButton(stop: stop, run: $run)
                    }
                }
            } else if let index = Adventure.chapters.firstIndex(of: chapter), index > 0 {
                let previous = Adventure.chapters[index - 1]
                Text("Earn \(Adventure.starsToUnlockNext(after: previous)) ★ in \(previous.continent.displayName) to unlock")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .opacity(unlocked ? 1 : 0.6)
    }
}

private struct StopButton: View {
    @Environment(AppModel.self) private var model
    let stop: Stop
    @Binding var run: Run?

    var body: some View {
        let unlocked = model.progress.isStopUnlocked(stop)
        let stars = model.progress.stars(for: stop)
        Button {
            model.markHintSeen(.mapStart)
            run = Run(kind: .stop(stop))
        } label: {
            VStack(spacing: 2) {
                Text("\(stop.number)").font(.headline)
                HStack(spacing: 1) {
                    ForEach(0..<Adventure.maxStarsPerStop, id: \.self) { index in
                        Image(systemName: index < stars ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(index < stars ? Theme.star : .secondary)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .background(unlocked ? Theme.accent.opacity(0.2) : Color.gray.opacity(0.15), in: Circle())
            .overlay(Circle().stroke(unlocked ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("Stop \(stop.number), \(stars) of 3 stars\(unlocked ? "" : ", locked")")
    }
}

@MainActor
enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.07, green: 0.16, blue: 0.32), Color(red: 0.05, green: 0.38, blue: 0.45)],
        startPoint: .top, endPoint: .bottom
    )
    static let card = Color(.secondarySystemBackground).opacity(0.95)
    static let accent = Color(red: 0.12, green: 0.62, blue: 0.82)
    static let star = Color(red: 1.0, green: 0.78, blue: 0.1)
    static let good = Color(red: 0.2, green: 0.75, blue: 0.4)
    static let bad = Color(red: 0.9, green: 0.3, blue: 0.3)
}

extension Hint {
    var title: String {
        switch self {
        case .mapStart: "Your adventure starts here"
        case .stars: "How stars work"
        case .daily: "New: Daily Challenge"
        }
    }

    var message: String {
        switch self {
        case .mapStart: "Tap stop 1 to begin. Earn stars to open new stops and continents."
        case .stars: "★★★ means no mistakes, ★★ one, ★ two. One star opens the next stop."
        case .daily: "Ten flags, the same for everyone today. Play every day to build a streak."
        }
    }
}

private struct HintCard: View {
    let hint: Hint
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.star)
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.title).font(.headline)
                Text(hint.message).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Got it", action: dismiss).font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.star.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}
