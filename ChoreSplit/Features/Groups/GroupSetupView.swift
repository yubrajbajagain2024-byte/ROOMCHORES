import SwiftUI
import SwiftData

/// Setting up a shared group, with everyone on their own phone: invite people, add the chores
/// you care about, rate what the others added, and the owner starts it when you're ready.
struct GroupSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    let household: Household

    @State private var showingInvite = false
    @State private var showingGroupMenu = false
    @State private var showingEditor = false
    @State private var showingStarters = false
    @State private var editingChore: Chore?
    @State private var ratingChore: Chore?
    @State private var confirmingStart = false

    private var me: Roommate? { household.sortedMembers.first { $0.id == sync.currentUserID } }
    private var myChores: [Chore] { household.activeChores.filter { $0.proposerID == sync.currentUserID } }
    private var toRate: [Chore] {
        guard let me else { return [] }
        return household.activeChores.filter { $0.proposerID != me.id && !$0.hasVoted(me) }
    }
    private var owner: Roommate? { household.sortedMembers.first(where: \.isOwner) }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                introCard
                inviteCard
                myChoresCard
                rateCard
                progressCard
            }
            .padding(.bottom, 24)
        }
        .background(Theme.feedBackground)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .refreshable { await sync.refresh() }
        .sheet(isPresented: $showingInvite) { InviteFriendsView(household: household) }
        .sheet(isPresented: $showingGroupMenu) { GroupSheet(household: household) }
        .sheet(isPresented: $showingEditor) { ChoreEditorView(household: household, author: me) }
        .sheet(isPresented: $showingStarters) { StarterChorePickerView(household: household, author: me) }
        .sheet(item: $editingChore) { chore in ChoreEditorView(household: household, author: me, existing: chore) }
        .sheet(item: $ratingChore) { chore in
            if let me { ChoreValueRatingView(chore: chore, household: household, rater: me) }
        }
        .confirmationDialog("Start \(household.name)?", isPresented: $confirmingStart, titleVisibility: .visible) {
            Button("Start and split the chores") { start() }
        } message: {
            Text("Everyone gets their first chores straight away. Anyone who joins later is included from their next turn.")
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Wordmark(size: 30)
            Spacer()
            Button { showingGroupMenu = true } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.chipFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Group menu")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.feedCard.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    @ViewBuilder
    private var startBar: some View {
        VStack(spacing: 6) {
            if me?.isOwner == true {
                PrimaryButton(title: "Start the group", systemImage: "play.fill", isEnabled: !household.activeChores.isEmpty) {
                    confirmingStart = true
                }
                Text(household.activeChores.isEmpty ? "Add at least one chore first." : "Hands out the first chores to everyone.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Label("Waiting for \(owner?.name ?? "the owner") to start the group", systemImage: "hourglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.feedCard.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    // MARK: - Cards

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up \(household.name)")
                .font(.system(size: 24, weight: .bold))
            Text("Everyone does this on their own phone: add the chores you care about, then rate what the others added. Ratings are anonymous — the chore ends up worth the average.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.feedCard)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeedSectionHeader(title: "Invite your roommates", subtitle: "Code \(GroupStore.formatted(household.inviteCode))",
                              actionTitle: "Share", action: { showingInvite = true })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(household.sortedMembers) { member in
                        VStack(spacing: 4) {
                            AvatarView(roommate: member, size: 48, showsRing: member.id == sync.currentUserID)
                            Text(member.id == sync.currentUserID ? "You" : member.shortName)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                    Button { showingInvite = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 48, height: 48)
                                .background(Circle().strokeBorder(Theme.brand.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            Text("Invite").font(.system(size: 12)).foregroundStyle(Theme.brand)
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    private var myChoresCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeedSectionHeader(title: "Your chores", subtitle: myChores.isEmpty ? "Add the jobs that bug you most when they're not done" : "\(myChores.count) added")

            ForEach(myChores) { chore in
                ChoreSummaryRow(chore: chore, household: household, showsProposer: false)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                    .onTapGesture { editingChore = chore }
                    .contextMenu {
                        Button("Edit") { editingChore = chore }
                        Button("Remove", role: .destructive) {
                            chore.isActive = false
                            try? context.save()
                            HouseholdActions.choreSaved(chore)
                        }
                    }
            }

            HStack(spacing: 10) {
                PrimaryButton(title: "New chore", systemImage: "plus") { showingEditor = true }
                SecondaryButton(title: "From a list") { showingStarters = true } icon: {
                    Image(systemName: "list.bullet").foregroundStyle(Theme.brand)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeedSectionHeader(title: "Rate the others' chores", subtitle: "Anonymous — nobody sees your numbers")

            if toRate.isEmpty {
                Text(household.activeChores.contains { $0.proposerID != sync.currentUserID }
                     ? "All rated. Nice."
                     : "Nothing yet — chores your roommates add show up here.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
            } else {
                ForEach(toRate) { chore in
                    Button { ratingChore = chore } label: {
                        HStack {
                            ChoreSummaryRow(chore: chore, household: household, hidePoints: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeedSectionHeader(title: "Who's added what")
            ForEach(household.sortedMembers) { member in
                let count = household.activeChores.filter { $0.proposerID == member.id }.count
                HStack(spacing: 12) {
                    AvatarView(roommate: member, size: 32)
                    Text(member.id == sync.currentUserID ? "You" : member.name)
                        .font(.system(size: 15))
                    Spacer()
                    Text(count == 0 ? "nothing yet" : "\(count) chore\(count == 1 ? "" : "s")")
                        .font(.system(size: 14))
                        .foregroundStyle(count == 0 ? Theme.secondaryText : Theme.green)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    // MARK: - Starting

    private func start() {
        household.setupStage = .running
        household.cycleStartDate = Calendar.current.startOfDay(for: Date())
        try? context.save()
        HouseholdActions.householdSaved(household)

        let plan = FairnessEngine.openingPlan(for: household)
        HouseholdActions.apply(plan, in: household, context: context)
        try? context.save()

        Task {
            await sync.flush()
            await NotificationService.shared.requestAuthorization()
        }
    }
}
