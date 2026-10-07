import Foundation

enum TrainerEditIssue: Equatable {
    case emptyName, unownedOutfit, invalidSlot
    var message: String {
        switch self {
        case .emptyName: "트레이너 이름을 입력해 주세요."
        case .unownedOutfit: "미소유 의상을 벗거나 소유한 의상으로 바꿔 주세요."
        case .invalidSlot: "의상에 맞는 슬롯을 선택해 주세요."
        }
    }
}

/// 미리보기는 이 값만 바꾼다. 저장 버튼을 누르기 전에는 스토어와 재화에 영향이 없다.
struct TrainerEditDraft: Equatable {
    var name: String
    var outfit: TrainerOutfit
    var normalizedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SaveTransfer.maxNameLength))
    }
    func validationIssue(owned: Set<OutfitItem>) -> TrainerEditIssue? {
        guard !normalizedName.isEmpty else { return .emptyName }
        guard outfit.worn.allSatisfy({ $0.key == $0.value.slot }) else { return .invalidSlot }
        guard outfit.worn.values.allSatisfy(owned.contains) else { return .unownedOutfit }
        return nil
    }
    mutating func select(_ item: OutfitItem?, in slot: OutfitSlot) {
        outfit.worn[slot] = item
        if item == nil { outfit.tints.removeValue(forKey: slot) }
    }
}

extension OutfitItem {
    func acquisitionDescription(l: L) -> String {
        if let price = shopPrice { return "상점 · 별의조각 \(price)" }
        for achievement in AchievementLadder.catalog {
            if let index = achievement.outfits.firstIndex(of: self) {
                return "업적 · \(l.achievementName(achievement.track)) · \(index + 1)단계"
            }
        }
        return "업적으로 해금"
    }
}
