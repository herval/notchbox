import Foundation

/// Stable IDs keep keyboard navigation and selection correct after closing a tab.
public struct TabSelection: Equatable {
    public private(set) var ids: [UUID] = []
    public private(set) var selected: UUID?
    public init() {}

    public mutating func append(_ id: UUID) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        selected = id
    }

    public mutating func select(_ id: UUID) {
        if ids.contains(id) { selected = id }
    }

    public mutating func select(index: Int) {
        guard ids.indices.contains(index) else { return }
        selected = ids[index]
    }

    public mutating func advance(by offset: Int) {
        guard !ids.isEmpty else { return }
        let current = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        selected = ids[((current + offset) % ids.count + ids.count) % ids.count]
    }

    public mutating func remove(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        if selected == id {
            selected = ids.isEmpty ? nil : ids[min(index, ids.count - 1)]
        }
    }
}
