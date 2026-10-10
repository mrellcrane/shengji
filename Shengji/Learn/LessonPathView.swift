import SwiftUI
import ShengjiCore

/// A lesson to open full screen, optionally at a given page (demo scenes open mid-lesson).
struct LessonLaunch: Identifiable {
    let lesson: Lesson
    var startPage: Int = 0
    /// Demo only: the answer shown as already picked on a predict start page.
    var demoAnswer: Int? = nil

    var id: String { lesson.id }
}

/// The Learn tab: streak, a "reviews due" banner, and the lessons as a path.
/// Each lesson is locked until the previous lesson's quiz is passed (mastery gating).
@MainActor
struct LessonPathView: View {
    @Environment(LearningStore.self) private var store
    @Environment(AchievementStore.self) private var achievements
    @Environment(AppRouter.self) private var router
    @State private var activeLesson: LessonLaunch?
    @State private var lockedLesson: Lesson?
    @State private var showsLockedAlert = false
    @State private var showsPrinciples = false
    @State private var showsSettings = false

    /// - Parameter initialLesson: a lesson to open straight away, the same way a tap opens it
    ///   (used by the `lesson` and `predict` demo scenes, so closing it returns to the path).
    init(initialLesson: LessonLaunch? = nil) {
        _activeLesson = State(initialValue: initialLesson)
    }

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LearnHeader(now: router.now) { lesson in
                        activeLesson = LessonLaunch(lesson: lesson)
                    }
                    LessonPath { lesson, state in
                        select(lesson, state: state)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .navigationTitle("Learn")
            .toolbar {
                toolbarContent
            }
        }
        .fullScreenCover(item: $activeLesson) { launch in
            LessonView(launch.lesson, startPage: launch.startPage, demoAnswer: launch.demoAnswer)
                .environment(store)
                .environment(router)
        }
        .sheet(isPresented: $showsPrinciples) {
            WhyThisWorksSheet()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
                .environment(store)
                .environment(achievements)
        }
        .alert("Lesson locked", isPresented: $showsLockedAlert, presenting: lockedLesson) { _ in
            Button("OK", role: .cancel) {}
        } message: { lesson in
            Text("Pass lesson \(max(1, lesson.number - 1))'s quiz to unlock this.")
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsPrinciples = true
            } label: {
                Label("Why this works", systemImage: "lightbulb")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private func select(_ lesson: Lesson, state: LessonState) {
        switch state {
        case .locked:
            lockedLesson = lesson
            showsLockedAlert = true
        case .available, .completed:
            activeLesson = LessonLaunch(lesson: lesson)
        }
    }
}

/// Streak, lessons passed, the banner that leads to the Review tab, and the next lesson
/// (once the path is long enough that it may sit below the fold).
@MainActor
private struct LearnHeader: View {
    @Environment(LearningStore.self) private var store
    @Environment(AppRouter.self) private var router
    let now: Date
    let onStart: (Lesson) -> Void

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        let due = store.dueCount(now: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LearnStreakBadge(days: store.streak(now: now))
                Spacer(minLength: 8)
                Text("\(completedCount) of \(Curriculum.lessons.count) lessons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(completedCount), total: Double(max(Curriculum.lessons.count, 1)))
                .tint(Theme.correct)
                .accessibilityLabel("\(completedCount) of \(Curriculum.lessons.count) lessons completed")
            if due > 0 {
                dueBanner(due)
            }
            if let next = upNext {
                upNextCard(next)
            }
        }
    }

    /// Lessons passed that are still in the course.
    private var completedCount: Int {
        min(store.progress.completedLessons.count, Curriculum.lessons.count)
    }

    /// The first lesson that is open but not passed yet, once two or more lessons are done.
    private var upNext: Lesson? {
        guard store.progress.completedLessons.count >= 2 else { return nil }
        return Curriculum.lessons.first { store.isUnlocked($0) && !store.isCompleted($0) }
    }

    private func upNextCard(_ lesson: Lesson) -> some View {
        Button {
            onStart(lesson)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next · Lesson \(lesson.number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lesson.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                Label("Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.felt, in: Capsule())
            }
            .padding(14)
            .background(Theme.felt.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.correct, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts the lesson")
    }

    private func dueBanner(_ due: Int) -> some View {
        Button {
            router.show(.review)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(TimePhrase.count(due, "review")) due")
                        .font(.headline)
                    Text("A quick recall now keeps it from fading.")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.usColor, Theme.usColor.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Review tab")
    }
}

/// The lessons in order, joined by a line.
@MainActor
private struct LessonPath: View {
    @Environment(LearningStore.self) private var store
    let onSelect: (Lesson, LessonState) -> Void

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        let lessons = Curriculum.lessons
        VStack(spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                let lessonState = state(of: lesson)
                LessonPathRow(lesson: lesson, state: lessonState, mastery: store.mastery(of: lesson),
                              isFirst: index == 0, isLast: index == lessons.count - 1) {
                    onSelect(lesson, lessonState)
                }
            }
        }
    }

    private func state(of lesson: Lesson) -> LessonState {
        if store.isCompleted(lesson) { return .completed }
        return store.isUnlocked(lesson) ? .available : .locked
    }
}

@MainActor
private struct LessonPathRow: View {
    let lesson: Lesson
    let state: LessonState
    let mastery: Double
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        HStack(alignment: .top, spacing: 12) {
            PathNode(number: lesson.number, state: state, isFirst: isFirst, isLast: isLast)
            Button(action: action) {
                LessonCard(lesson: lesson, state: state, mastery: mastery)
            }
            .buttonStyle(.plain)
            .padding(.bottom, isLast ? 0 : 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The circle on the path: number, checkmark or lock, with the connecting line.
@MainActor
private struct PathNode: View {
    let number: Int
    let state: LessonState
    let isFirst: Bool
    let isLast: Bool

    private var lineColor: Color { Color.secondary.opacity(0.3) }

    private var fill: Color {
        switch state {
        case .locked: return Color.secondary.opacity(0.18)
        case .available: return Theme.felt
        case .completed: return Theme.correct
        }
    }

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : lineColor)
                .frame(width: 3, height: 14)
            ZStack {
                Circle()
                    .fill(fill)
                symbol
            }
            .frame(width: 40, height: 40)
            Rectangle()
                .fill(isLast ? Color.clear : lineColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 40)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var symbol: some View {
        switch state {
        case .locked:
            Image(systemName: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .available:
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
        case .completed:
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

/// One lesson on the path.
@MainActor
private struct LessonCard: View {
    let lesson: Lesson
    let state: LessonState
    let mastery: Double

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Lesson \(lesson.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Label("\(lesson.estimatedMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(lesson.title)
                .font(.headline)
            Text(lesson.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let term = lesson.chineseTerm {
                Text(term)
                    .font(.footnote)
                    .foregroundStyle(Theme.cardRed)
            }
            footer
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: shape)
        .overlay {
            shape.strokeBorder(border, lineWidth: state == .available ? 2 : 1)
        }
        .opacity(state == .locked ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hintText)
    }

    private var background: Color {
        state == .available ? Theme.felt.opacity(0.08) : Color.secondary.opacity(0.07)
    }

    private var border: Color {
        switch state {
        case .locked: return Color.secondary.opacity(0.15)
        case .available: return Theme.correct
        case .completed: return Theme.correct.opacity(0.35)
        }
    }

    private var hintText: String {
        switch state {
        case .locked: return "Locked. Pass lesson \(max(1, lesson.number - 1))'s quiz to unlock this."
        case .available: return "Starts the lesson."
        case .completed: return "Completed. Opens the lesson again."
        }
    }

    @ViewBuilder private var footer: some View {
        switch state {
        case .locked:
            Label("Locked", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .available:
            HStack {
                Spacer()
                Label("Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Theme.felt, in: Capsule())
            }
        case .completed:
            HStack(spacing: 10) {
                MasteryRing(value: mastery, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                    Text("Mastery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label("Review", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.correct)
            }
        }
    }
}
