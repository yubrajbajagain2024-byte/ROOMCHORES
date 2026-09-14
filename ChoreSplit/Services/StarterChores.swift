import Foundation

/// A starting library so setup does not begin with a blank page. Everything here is a
/// suggestion with a sensible opening estimate — the household still rates each one, so
/// these numbers are a conversation starter, not a verdict.
struct StarterChore {
    let title: String
    let category: ChoreCategory
    let recurrence: Recurrence
    let difficulty: Int
    let labor: Int
    let minutes: Int
}

enum StarterChores {
    static let all: [StarterChore] = [
        StarterChore(title: "Wash up after dinner", category: .kitchen, recurrence: .daily, difficulty: 2, labor: 2, minutes: 20),
        StarterChore(title: "Empty and refill the dishwasher", category: .kitchen, recurrence: .daily, difficulty: 1, labor: 2, minutes: 10),
        StarterChore(title: "Wipe down the kitchen counters", category: .kitchen, recurrence: .daily, difficulty: 1, labor: 1, minutes: 10),
        StarterChore(title: "Clean the oven", category: .kitchen, recurrence: .monthly, difficulty: 5, labor: 4, minutes: 60),
        StarterChore(title: "Clean out the fridge", category: .kitchen, recurrence: .biweekly, difficulty: 4, labor: 2, minutes: 30),
        StarterChore(title: "Mop the kitchen floor", category: .kitchen, recurrence: .weekly, difficulty: 2, labor: 3, minutes: 20),

        StarterChore(title: "Scrub the toilet", category: .bathroom, recurrence: .weekly, difficulty: 4, labor: 3, minutes: 15),
        StarterChore(title: "Clean the shower and bath", category: .bathroom, recurrence: .weekly, difficulty: 4, labor: 4, minutes: 30),
        StarterChore(title: "Clean the bathroom sink and mirror", category: .bathroom, recurrence: .weekly, difficulty: 2, labor: 2, minutes: 15),
        StarterChore(title: "Restock loo roll and soap", category: .bathroom, recurrence: .weekly, difficulty: 1, labor: 1, minutes: 5),

        StarterChore(title: "Vacuum the living room", category: .living, recurrence: .weekly, difficulty: 2, labor: 3, minutes: 25),
        StarterChore(title: "Vacuum the hallway and stairs", category: .living, recurrence: .weekly, difficulty: 2, labor: 4, minutes: 20),
        StarterChore(title: "Dust and tidy shared shelves", category: .living, recurrence: .weekly, difficulty: 2, labor: 1, minutes: 20),
        StarterChore(title: "Clean the windows", category: .living, recurrence: .monthly, difficulty: 3, labor: 3, minutes: 45),

        StarterChore(title: "Wash the shared towels", category: .laundry, recurrence: .weekly, difficulty: 1, labor: 2, minutes: 15),
        StarterChore(title: "Wash and hang the tea towels", category: .laundry, recurrence: .weekly, difficulty: 1, labor: 1, minutes: 10),

        StarterChore(title: "Take the bins out", category: .trash, recurrence: .weekly, difficulty: 1, labor: 3, minutes: 10),
        StarterChore(title: "Sort the recycling", category: .trash, recurrence: .weekly, difficulty: 2, labor: 2, minutes: 15),
        StarterChore(title: "Empty the food waste caddy", category: .trash, recurrence: .everyOtherDay, difficulty: 3, labor: 1, minutes: 5),

        StarterChore(title: "Sweep the front step and porch", category: .outdoor, recurrence: .biweekly, difficulty: 1, labor: 3, minutes: 20),
        StarterChore(title: "Water the plants", category: .outdoor, recurrence: .everyOtherDay, difficulty: 1, labor: 1, minutes: 10),

        StarterChore(title: "Do the household grocery run", category: .admin, recurrence: .weekly, difficulty: 3, labor: 4, minutes: 60),
        StarterChore(title: "Deal with post and shared bills", category: .admin, recurrence: .weekly, difficulty: 3, labor: 1, minutes: 20)
    ]

    static func suggestions(excluding existingTitles: Set<String>, category: ChoreCategory? = nil) -> [StarterChore] {
        all.filter { starter in
            !existingTitles.contains(starter.title.lowercased())
                && (category == nil || starter.category == category)
        }
    }
}
