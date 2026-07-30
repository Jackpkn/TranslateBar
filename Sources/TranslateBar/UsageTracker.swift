import Foundation

struct DeepLUsageResponse: Decodable {
    let characterCount: Int
    let characterLimit: Int

    enum CodingKeys: String, CodingKey {
        case characterCount = "character_count"
        case characterLimit = "character_limit"
    }
}

final class UsageTracker {
    static let shared = UsageTracker()

    private(set) var characterCount: Int = 0
    private(set) var characterLimit: Int = 500000

    var usagePercentage: Double {
        guard characterLimit > 0 else { return 0 }
        return (Double(characterCount) / Double(characterLimit)) * 100.0
    }

    var usageString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let countStr = formatter.string(from: NSNumber(value: characterCount)) ?? "\(characterCount)"
        let limitStr = formatter.string(from: NSNumber(value: characterLimit)) ?? "\(characterLimit)"
        let percentStr = String(format: "%.1f", usagePercentage)
        return "\(countStr) / \(limitStr) chars (\(percentStr)%)"
    }

    private init() {}

    func updateUsage(count: Int, limit: Int) {
        self.characterCount = count
        self.characterLimit = limit
    }
}
