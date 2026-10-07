import SwiftUI

enum TrainerEditorMode { case creation, editing }

/// 최초 화면은 부모 팝오버가, 편집기는 자체 본문이 스크롤을 소유한다.
struct TrainerEditorFields: View {
    let store: CompanionStore
    let mode: TrainerEditorMode
    @Binding var draft: TrainerEditDraft
    @State private var slot: OutfitSlot = .hat
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.l.trainerNamePrompt).font(.callout.weight(.semibold))
            TextField(store.l.trainerNamePlaceholder, text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft.name) { draft.name = String(draft.name.prefix(20)) }
            TrainerPreviewView(outfit: draft.outfit)
            Text("기본 머리").font(.callout.weight(.semibold))
            Picker("기본 머리", selection: $draft.outfit.appearance.baseHair) {
                ForEach(TrainerBaseHair.allCases, id: \.self) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text("피부색").font(.callout.weight(.semibold))
            LazyVGrid(columns: columns) {
                ForEach(TrainerSkinTone.allCases, id: \.self) { tone in
                    colorChoice(tone.name, rgb: tone.colors.base, selected: draft.outfit.appearance.skinTone == tone) {
                        draft.outfit.appearance.skinTone = tone
                    }
                }
            }
            Text("머리색").font(.callout.weight(.semibold))
            LazyVGrid(columns: columns) {
                ForEach(TrainerHairColor.allCases, id: \.self) { color in
                    colorChoice(color.name, rgb: color.colors.base, selected: draft.outfit.appearance.hairColor == color) {
                        draft.outfit.appearance.hairColor = color
                    }
                }
            }
            if mode == .editing { wardrobe }
        }
    }

    private var wardrobe: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("의상").font(.callout.weight(.semibold))
            Picker("의상 슬롯", selection: $slot) {
                ForEach([OutfitSlot.hat, .hair, .top, .bottom, .accessory], id: \.self) {
                    Text(store.l.outfitSlotName($0)).tag($0)
                }
            }.pickerStyle(.segmented).labelsHidden()
            Button(store.l.outfitTakeOff) { draft.select(nil, in: slot) }
                .buttonStyle(.bordered).controlSize(.small)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                ForEach(OutfitItem.allCases.filter { $0.slot == slot }, id: \.self) { item in
                    Button { draft.select(item, in: slot) } label: {
                        VStack(spacing: 4) {
                            TrainerAvatarView(outfit: thumbnail(item), scale: 2)
                            Text(store.l.outfitItemName(item)).font(.caption2)
                            if !store.ownsOutfit(item) { Image(systemName: "lock.fill").font(.caption2) }
                        }.frame(maxWidth: .infinity)
                            .padding(6)
                            .background(draft.outfit.worn[slot] == item ? Color.accentColor.opacity(0.18) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(store.l.outfitItemName(item) + (store.ownsOutfit(item) ? "" : " · 미소유"))
                }
            }
            if let item = draft.outfit.worn[slot] {
                Text(item.acquisitionDescription(l: store.l)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if slot == .hair {
                    Text("머리 의상에도 위에서 고른 머리색이 적용됩니다.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("의상 색상 · 무료").font(.callout.weight(.semibold))
                    Button("원래 색") { draft.outfit.tints[slot] = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                    LazyVGrid(columns: columns) {
                        ForEach(OutfitTint.allCases, id: \.self) { tint in
                            colorChoice(tint.name, rgb: tint.colors.base, selected: draft.outfit.tints[slot] == tint) {
                                draft.outfit.tints[slot] = tint
                            }
                        }
                    }
                }
            }
        }
    }

    private func thumbnail(_ item: OutfitItem) -> TrainerOutfit {
        TrainerOutfit(worn: [item.slot: item], appearance: draft.outfit.appearance,
                      tints: draft.outfit.tints[item.slot].map { [item.slot: $0] } ?? [:])
    }

    private func colorChoice(_ name: String, rgb: UInt32, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(Color(red: Double((rgb >> 16) & 255) / 255,
                                        green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255))
                    Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                    if selected { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black).font(.caption) }
                }.frame(width: 24, height: 24)
                Text(name).font(.caption2).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, 3)
        }.buttonStyle(.plain).accessibilityLabel(name + (selected ? " · 선택됨" : ""))
    }
}
