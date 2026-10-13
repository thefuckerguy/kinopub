import Foundation

@MainActor
final class WatchLaterStore: ObservableObject {
    @Published private(set) var items: [CatalogItem]

    private let defaults: UserDefaults
    private let storageKey = "watchLaterCatalogItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let savedItems = try? JSONDecoder().decode([CatalogItem].self, from: data) {
            items = Self.uniqueItems(savedItems)
        } else {
            items = []
        }
    }

    func contains(_ item: CatalogItem) -> Bool {
        contains(id: item.id.value)
    }

    func contains(id: String) -> Bool {
        items.contains { $0.id.value == id }
    }

    @discardableResult
    func toggle(_ item: CatalogItem) -> Bool {
        if let index = items.firstIndex(where: { $0.id.value == item.id.value }) {
            items.remove(at: index)
            persist()
            return false
        }

        items.insert(item, at: 0)
        persist()
        return true
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func uniqueItems(_ savedItems: [CatalogItem]) -> [CatalogItem] {
        var seen = Set<String>()
        return savedItems.filter { seen.insert($0.id.value).inserted }
    }
}

@MainActor
final class PersonalViewingStore: ObservableObject {
    @Published private(set) var items: [CatalogItem]

    private let defaults: UserDefaults
    private let storageKey = "personalViewingCatalogItems.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let savedItems = try? JSONDecoder().decode([CatalogItem].self, from: data) {
            items = Self.uniqueItems(savedItems)
        } else {
            items = []
        }
    }

    func contains(_ item: CatalogItem) -> Bool {
        contains(id: item.id.value)
    }

    func contains(id: String) -> Bool {
        items.contains { $0.id.value == id }
    }

    @discardableResult
    func toggle(_ item: CatalogItem) -> Bool {
        if let index = items.firstIndex(where: { $0.id.value == item.id.value }) {
            items.remove(at: index)
            persist()
            return false
        }

        items.insert(item, at: 0)
        persist()
        return true
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func uniqueItems(_ savedItems: [CatalogItem]) -> [CatalogItem] {
        var seen = Set<String>()
        return savedItems.filter { seen.insert($0.id.value).inserted }
    }
}
