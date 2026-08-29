import AppKit

/// R7's art boundary: furniture is bundled, never fetched.  Keeping this loader separate from
/// SpriteLoader ensures a disconnected user can still decorate their room.
enum MemoryHomeBundledArt {
    static let interiorTilesetResource = "oga-interior-tileset"

    /// Source rectangles are deliberately kept here, next to the resource contract, rather than
    /// in the SwiftUI screen.  This makes it impossible for the room UI to silently fall back to
    /// SF Symbols/emoji when the bundled art changes.
    private static let furnitureRects: [ItemKind: CGRect] = [
        .roomBed: CGRect(x: 64, y: 16, width: 24, height: 16),
        .roomTable: CGRect(x: 88, y: 32, width: 16, height: 16),
        .roomLamp: CGRect(x: 112, y: 16, width: 8, height: 16),
        // The bundled OGA interior sheet is a compact pixel atlas. These deliberately reuse
        // compatible tiles from it, keeping every style fully offline while the art pipeline
        // remains a single audited resource.
        .lovelyVanity: CGRect(x: 88, y: 32, width: 16, height: 16),
        .lovelySofa: CGRect(x: 64, y: 16, width: 24, height: 16),
        .lovelyHeartLamp: CGRect(x: 112, y: 16, width: 8, height: 16),
        .retroArcade: CGRect(x: 88, y: 32, width: 16, height: 16),
        .retroRadio: CGRect(x: 112, y: 16, width: 8, height: 16),
        .retroTV: CGRect(x: 64, y: 16, width: 24, height: 16),
        .naturePlant: CGRect(x: 112, y: 16, width: 8, height: 16),
        .natureBench: CGRect(x: 64, y: 16, width: 24, height: 16),
        .natureLantern: CGRect(x: 88, y: 32, width: 16, height: 16),
    ]

    private static let cachedInteriorTileset: NSImage? = {
        guard let url = Bundle.module.url(forResource: interiorTilesetResource, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    static func interiorTileset() -> NSImage? { cachedInteriorTileset }

    /// A small, nearest-neighbour-ready furniture sprite. The tileset's origin is top-left,
    /// matching `CGImage.cropping(to:)`; AppKit's view coordinate system is not involved.
    static func furnitureImage(for item: ItemKind) -> NSImage? {
        guard let rect = furnitureRects[item],
              let image = interiorTileset(),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}
