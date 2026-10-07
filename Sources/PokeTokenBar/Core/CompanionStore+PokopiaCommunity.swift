import Foundation

@MainActor extension CompanionStore {
    func pokopiaCommunityContext() -> PokopiaCommunityContext {
        var seen: Set<Int> = []
        let brushes = Set(dexEntries.filter { seen.insert($0.finalID).inserted }.compactMap {
            PokopiaTown.brush(dittoFormTypes: $0.types)
        })
        let canShare = PokopiaCrafting.dishes.contains { itemCount($0) > 0 }
            || state.townCraft.map { PokopiaCrafting.dishes.contains($0.output) } == true
            || PokopiaCrafting.recipes.contains { $0.satietyHours != nil && canStartTownCraft($0) }
        return .init(dayKey: pokopiaCommunityDayKey, towns: memoryAlbum.pokopia.towns,
                     availableBrushes: brushes, canShareFood: canShare)
    }

    func refreshPokopiaCommunity() {
        let context = pokopiaCommunityContext()
        updatePokopiaCommunity { community, _ in
            let issued = PokopiaCommunity.prepare(&community, context: context)
            let milestones = PokopiaCommunity.refreshMilestones(&community, towns: context.towns)
            return issued || milestones
        }
    }

    func recordPokopiaFocus(minutes: Int, saveImmediately: Bool = true) {
        let dayKey = pokopiaCommunityDayKey
        updatePokopiaCommunity(saveImmediately: saveImmediately) { community, _ in
            PokopiaCommunity.recordFocusMinutes(minutes, dayKey: dayKey, in: &community)
        }
    }

    func recordPokopiaMeal(region: TownRegion, saveImmediately: Bool = true) {
        let dayKey = pokopiaCommunityDayKey
        updatePokopiaCommunity(saveImmediately: saveImmediately) { community, _ in
            PokopiaCommunity.recordMeal(region: region, dayKey: dayKey, in: &community)
        }
    }

    func claimPokopiaRequest(id: String) -> PokopiaReward? {
        refreshPokopiaCommunity()
        let context = pokopiaCommunityContext()
        var reward: PokopiaReward?
        updatePokopiaCommunity { community, inventory in
            guard let request = community.daily?.requests.first(where: { $0.id == id }),
                  // 같은 상한을 SaveTransfer.sanitized가 적용한다.
                  (0..<999).contains(inventory[request.reward.rawValue, default: 0]),
                  let claimed = PokopiaCommunity.claim(requestID: id, context: context, in: &community) else { return false }
            inventory[claimed.item.rawValue, default: 0] += 1
            reward = claimed
            return true
        }
        return reward
    }
}
