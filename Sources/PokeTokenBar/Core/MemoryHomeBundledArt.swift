import AppKit

/// R7's art boundary: furniture is bundled, never fetched.  Keeping this loader separate from
/// SpriteLoader ensures a disconnected user can still decorate their room.
enum MemoryHomeBundledArt {
    static let interiorTilesetResource = "oga-interior-tileset"

    static func interiorTileset() -> NSImage? {
        guard let url = Bundle.module.url(forResource: interiorTilesetResource, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
