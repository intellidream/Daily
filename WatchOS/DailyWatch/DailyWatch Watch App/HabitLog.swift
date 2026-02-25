import Foundation

struct HabitLog: Codable, Identifiable {
    var id: UUID = UUID()
    var user_id: UUID?
    var habit_type: String
    var value: Double
    var unit: String
    var logged_at: String // ISO8601 string
    var metadata: String?
    
    // Coding keys if needed
}
