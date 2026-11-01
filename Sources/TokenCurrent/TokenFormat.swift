#if os(macOS)
import Foundation

enum TokenFormat {
    static func compact(_ value: Double) -> String {
        let scale: Double
        let suffix: String
        if value >= 1_000_000_000_000 { scale = 1_000_000_000_000; suffix = "T" }
        else if value >= 1_000_000_000 { scale = 1_000_000_000; suffix = "B" }
        else if value >= 1_000_000 { scale = 1_000_000; suffix = "M" }
        else if value >= 1_000 { scale = 1_000; suffix = "k" }
        else { scale = 1; suffix = "" }
        let decimals = scale == 1 && (value == 0 || value >= 10) ? 0 : 1
        return (value / scale).formatted(.number.precision(.fractionLength(0...decimals))) + suffix
    }
    static func rate(_ value: Double?) -> String { value.map(compact) ?? "—" }
}
#endif
