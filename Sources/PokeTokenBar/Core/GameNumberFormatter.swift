import Foundation

enum GameNumberFormatter {
    static func compact(_ value: Int) -> String {
        let number = Double(value)
        let magnitude: (divisor: Double, suffix: String, digits: Int)?
        switch abs(value) {
        case 1_000_000_000...: magnitude = (1_000_000_000, "B", 2)
        case 1_000_000...: magnitude = (1_000_000, "M", 1)
        case 10_000...: magnitude = (1_000, "K", 1)
        default: magnitude = nil
        }
        guard let magnitude else { return value.formatted(.number.grouping(.never)) }
        let scaled = number / magnitude.divisor
        return scaled.formatted(.number.precision(.fractionLength(0...magnitude.digits))) + magnitude.suffix
    }
}
