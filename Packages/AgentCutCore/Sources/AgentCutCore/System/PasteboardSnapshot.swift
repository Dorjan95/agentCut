import AppKit

/// Copia completa degli appunti (tutti gli elementi, tutti i tipi) da ripristinare dopo ⌘C/⌘V sintetici.
public struct PasteboardSnapshot: @unchecked Sendable {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    public init(capturing pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
