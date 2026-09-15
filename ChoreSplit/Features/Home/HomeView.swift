import SwiftUI
import SwiftData

/// The whole app after setup: one feed. Scoreboard, your tasks, then other people's finished
/// tasks waiting for your rating.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Present for a shared group; absent for the on-device demo.
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    let household: Household

    @State private var showingSwitcher = false
    @State private var showingAddTask = false
    @State private var selectedAssignment: Assignment?
    @State private var scoreDetail: Roommate?
    /// The task being finished — it needs a video before it can be marked done.
    @State private var finishing: Assignment?

    private var me: Roommate? { appState.activeRoommate(in: household) }

    private var myTasks: [Assignment] {
        guard let me else { return [] }
        return (household.assignments ?? [])
            .filter { $0.status == .open && $0.assignee?.id == me.id }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var toRate: [Assignment] {
        guard let me else { return [] }
        return Scores.awaitingRating(from: me, in: household)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    scoreboardSection
                    tasksSection
                    ratingsSection.id("ratings")
                }
                .padding(.bottom, 32)
            }
            #if DEBUG
            // `--scroll-to-ratings` brings the rating cards on screen, for checking them in a
            // simulator that can't be scrolled by hand.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--scroll-to-ratings") else { return }
                try? await Task.sleep(for: .seconds(1))
                withAnimation { proxy.scrollTo("ratings", anchor: .top) }
            }
            #endif
        }
        .background(Theme.feedBackground)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .refreshable {
            if let sync {
                await sync.maintain()
            } else {
                HouseholdActions.runMaintenance(for: household, context: context)
            }
        }
        .sheet(isPresented: $showingSwitcher) {
            if sync != nil {
                GroupSheet(household: household)
            } else {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingAddTask) {
            if let me {
                AddTaskSheet(household: household, creator: me)
            }
        }
        .sheet(item: $selectedAssignment) { assignment in
            AssignmentDetailView(assignment: assignment, household: household)
        }
        .sheet(item: $finishing) { task in
            CompleteTaskSheet(assignment: task, household: household)
        }
        .sheet(item: $scoreDetail) { roommate in
            ScoreDetailSheet(roommate: roommate, household: household, isMe: roommate.id == me?.id)
        }
        .onChange(of: appState.pendingAssignmentID) { _, id in
            guard let id,
                  let match = (household.assignments ?? []).first(where: { $0.id == id })
            else { return }
            selectedAssignment = match
            appState.pendingAssignmentID = nil
        }
        .task {
            // A shared group's maintenance runs in SharedGroupRoot, coordinated with other phones.
            if sync == nil {
                HouseholdActions.runMaintenance(for: household, context: context)
            }
            // Skipped in the demo and the preview so the permission alert doesn't sit over the
            // screen while the app is being driven for screenshots.
            let arguments = ProcessInfo.processInfo.arguments
            if !arguments.contains("--demo") && !arguments.contains("--preview-shared") {
                await NotificationService.shared.requestAuthorization()
            }
            #if DEBUG
            // `--add-task`, `--scores` and `--complete` open those sheets on launch, for checking layout
            // in a simulator.
            if arguments.contains("--add-task") { showingAddTask = true }
            if arguments.contains("--scores") { scoreDetail = Scores.board(for: household).first?.roommate }
            if arguments.contains("--complete") { finishing = myTasks.first }
            #endif
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("choresplit")
                .font(.system(size: 30, weight: .heavy))
                .tracking(-1.2)
                .foregroundStyle(Theme.brand)

            Spacer()

            RoundIconButton(systemName: "plus", label: "Add a task") { showingAddTask = true }
            RoundIconButton(systemName: "person.2.fill",
                            label: sync != nil ? "Group menu" : "Switch roommate. Currently \(me?.name ?? "nobody")") {
                showingSwitcher = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.feedCard.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Scoreboard

    private var scoreboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeedSectionHeader(title: "Scoreboard", subtitle: household.cycleLengthDays == 7 ? "This week" : "This cycle")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Scores.board(for: household).enumerated()), id: \.element.id) { rank, entry in
                        Button {
                            scoreDetail = entry.roommate
                        } label: {
                            ScoreCard(entry: entry, rank: rank, isMe: entry.roommate.id == me?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSectionHeader(
                title: "Your tasks",
                subtitle: myTasks.isEmpty ? nil : "\(myTasks.count) to do",
                actionTitle: "Add",
                action: { showingAddTask = true }
            )
            .padding(.bottom, 6)

            if myTasks.isEmpty {
                Text("You're all caught up.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(myTasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 56)
                    }
                    TaskRow(
                        assignment: task,
                        onFinish: { finishing = task },
                        onSkip: { HouseholdActions.markSkipped(task, context: context) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedAssignment = task }
                }
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    // MARK: - Ratings

    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSectionHeader(
                title: "Give ratings",
                subtitle: "Anonymous — nobody sees who rated what"
            )
            .padding(.bottom, 10)

            let pending = toRate
            if pending.isEmpty {
                Text("Nothing to rate. When a roommate finishes a task, it shows up here.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else if let me {
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, assignment in
                    if index > 0 {
                        Rectangle().fill(Theme.feedBackground).frame(height: 8)
                    }
                    RateTaskCard(assignment: assignment, household: household, rater: me)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
        .animation(.snappy, value: toRate.map(\.id))
    }
}

// MARK: - Pieces

private struct RoundIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.chipFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FeedSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.brand)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// A story-sized card: who, where they rank, and what they've earned.
private struct ScoreCard: View {
    let entry: ScoreEntry
    let rank: Int
    let isMe: Bool

    var body: some View {
        let color = entry.roommate.color

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle().fill(.white)
                        Text(entry.roommate.emoji).font(.system(size: 19))
                    }
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(isMe ? Theme.brand : .white.opacity(0.9), lineWidth: 3).padding(-3))

                    Spacer()

                    if rank == 0 && entry.thisCycle > 0 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.yellow)
                            .shadow(radius: 2)
                            .accessibilityLabel("Leading")
                    } else {
                        Text("#\(rank + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer()

                Text(PointsEngine.format(entry.thisCycle))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("pts · \(entry.tasksThisCycle) task\(entry.tasksThisCycle == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 4)
                Text(isMe ? "You" : entry.roommate.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(width: 108, height: 172)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isMe ? "You" : entry.roommate.name), \(PointsEngine.format(entry.thisCycle)) points, rank \(rank + 1)")
        .accessibilityHint("Shows points for each task")
    }
}

private struct TaskRow: View {
    let assignment: Assignment
    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onFinish) {
                Image(systemName: "circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish \(assignment.title) with a video")

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(assignment.isOverdue ? "Overdue · \(assignment.dueDescription)" : assignment.dueDescription)
                        .foregroundStyle(assignment.isOverdue ? Theme.rose : Theme.secondaryText)
                    if assignment.reminderDate != nil {
                        Image(systemName: assignment.voiceReminderEnabled ? "waveform" : "bell.fill")
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityLabel(assignment.voiceReminderEnabled ? "Voice reminder set" : "Reminder set")
                    }
                }
                .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(assignment.pointsQuoted) pts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.chipFill))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            Button(action: onFinish) {
                Label("Finish with a video…", systemImage: "video.badge.checkmark")
            }
            Button(role: .destructive, action: onSkip) {
                Label("Skip this one", systemImage: "xmark.circle")
            }
        }
    }
}
