import Foundation

enum PokemonNameSearch {
    static func matches(_ query: String, names: [String]) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return names.contains { normalized($0).contains(needle) }
    }

    static func names(for mon: MonState, resolvedSpeciesName: String? = nil) -> [String] {
        var result = mon.names?.values.flatMap(\.values) ?? []
        if let nickname = mon.nickname { result.append(nickname) }
        if let resolvedSpeciesName { result.append(resolvedSpeciesName) }
        result.append("#\(mon.currentID)")
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
            .lowercased()
    }
}
