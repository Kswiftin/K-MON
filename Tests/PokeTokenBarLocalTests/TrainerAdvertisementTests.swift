import Foundation
import Network
import Testing
@testable import PokeTokenBar

@Suite("트레이너 외형 광고 호환")
struct TrainerAdvertisementTests {
    @Test func appearanceOnlyAdvertisementSurvives() {
        let outfit = TrainerOutfit(appearance: .creationDefault)
        let sent = PeerAdvertisement(outfit: outfit)
        #expect(sent.txtRecord["outfit"] == nil)
        #expect(sent.txtRecord["appearance"] == "hair:short")
        #expect(PeerAdvertisement(sent.txtRecord).outfit == outfit)
    }

    @Test func allThreeKeysRoundTrip() {
        let outfit = TrainerOutfit(worn: [.hat: .capRed, .top: .hoodie],
            appearance: TrainerAppearance(baseHair: .curly, skinTone: .darkBrown, hairColor: .silver),
            tints: [.hat: .purple, .top: .pink])
        let sent = PeerAdvertisement(rankPoints: 7, outfit: outfit)
        #expect(sent.txtRecord["outfit"] == "hat:cap_red,top:hoodie")
        #expect(sent.txtRecord["appearance"] == "hair:curly,skin:darkBrown,hairColor:silver")
        #expect(sent.txtRecord["outfitTint"] == "hat:purple,top:pink")
        #expect(PeerAdvertisement(sent.txtRecord) == sent)
        // 구버전은 기존 키만 읽고 알고 있는 의상을 그대로 표시한다.
        #expect(TrainerOutfit(wireString: sent.txtRecord["outfit"]!).worn == [.hat: .capRed, .top: .hoodie])
    }

    @Test func defaultFieldsOmitKeys() {
        let plain = PeerAdvertisement(outfit: TrainerOutfit())
        #expect(plain.outfit == nil)
        #expect(plain.txtRecord.dictionary.isEmpty)
        let worn = PeerAdvertisement(outfit: TrainerOutfit(worn: [.hat: .capRed]))
        #expect(worn.txtRecord["appearance"] == nil)
        #expect(worn.txtRecord["outfitTint"] == nil)
    }

    @Test func legacyAdvertisementKeepsDefaultAppearance() {
        let old = PeerAdvertisement(NWTXTRecord(["outfit": "hat:cap_red", "rankPoints": "7"]))
        #expect(old.outfit == TrainerOutfit(worn: [.hat: .capRed]))
        #expect(old.rankPoints == 7)
    }

    @Test func unknownFieldsDoNotDropPeer() {
        let record = NWTXTRecord(["rankPoints": "7", "outfit": "hat:cap_red,top:future,garbage",
            "appearance": "hair:curly,skin:future,hairColor:blue,unknown:3",
            "outfitTint": "hat:pink,top:green,hair:red,future:black"])
        let parsed = PeerAdvertisement(record)
        #expect(parsed.rankPoints == 7)
        #expect(parsed.outfit?.worn == [.hat: .capRed])
        #expect(parsed.outfit?.appearance == TrainerAppearance(baseHair: .curly, hairColor: .blue))
        #expect(parsed.outfit?.tints == [.hat: .pink])
        #expect(PeerAdvertisement(NWTXTRecord(["appearance": "garbage"])).outfit == nil)
    }

    @Test func samePeerAppearanceChangesEquality() {
        let endpoint = NWEndpoint.service(name: "트레이너#123456", type: "_poke-token._tcp", domain: "local.", interface: nil)
        let a = BattlePeer(name: "트레이너", serviceName: "트레이너#123456", endpoint: endpoint,
            advertisement: PeerAdvertisement(outfit: TrainerOutfit()))
        let b = BattlePeer(name: "트레이너", serviceName: "트레이너#123456", endpoint: endpoint,
            advertisement: PeerAdvertisement(outfit: TrainerOutfit(appearance: .creationDefault)))
        #expect(a.id == b.id)
        #expect(a != b)
        let c = BattlePeer(name: b.name, serviceName: b.serviceName, endpoint: endpoint,
            advertisement: PeerAdvertisement(outfit: TrainerOutfit(worn: [.hat: .capRed], tints: [.hat: .green])))
        let d = BattlePeer(name: c.name, serviceName: c.serviceName, endpoint: endpoint,
            advertisement: PeerAdvertisement(outfit: TrainerOutfit(worn: [.hat: .capRed], tints: [.hat: .pink])))
        #expect(c.id == d.id)
        #expect(c != d)
    }

    @Test func maximumRecordFitsBonjourLimits() {
        let outfit = TrainerOutfit(worn: [.hat: .helmetExplorer, .hair: .hairMessy, .top: .stripedTee,
            .bottom: .shortsKhaki, .accessory: .crossbodyBag],
            appearance: TrainerAppearance(baseHair: .curly, skinTone: .lightApricot, hairColor: .auburn),
            tints: [.hat: .purple, .top: .yellow, .bottom: .purple, .accessory: .purple])
        let record = PeerAdvertisement(rankPoints: 999, trainerLevel: 99, achievementTiers: 9, achievementCeiling: 24,
            outfit: outfit, representativeSpeciesID: 9999, representativeIsShiny: true,
            runBestWave: 30, runFinalWave: 30, runClears: 999, beginnerMode: true).txtRecord
        for (key, value) in record.dictionary { #expect(key.utf8.count + 1 + value.utf8.count <= 255) }
        #expect(record.data.count < 1_024)
        #expect(PeerAdvertisement(record).outfit == outfit)
    }
}
