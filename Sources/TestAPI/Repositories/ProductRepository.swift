import Vapor
import Foundation

actor ProductRepository {
    private var products: [UUID: Product]
    private var listeners: [UUID: AsyncStream<ProductEventNotification>.Continuation]

    init() {
        self.listeners = [:]
        self.products = Self.createDefaultSamples()
    }

    private static func createDefaultSamples() -> [UUID: Product] {
        let samples: [Product] = [
            Product(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "Ultra-Light Laptop Pro 16",
                description: "Next-gen laptop with 16-inch Retina display, 32GB RAM, and 1TB SSD.",
                price: 1899.99,
                category: .electronics,
                sku: "TECH-LAP-001",
                stockQuantity: 25,
                tags: ["apple", "macbook", "pro", "laptop"]
            ),
            Product(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "Wireless Noise-Cancelling Headphones",
                description: "Premium over-ear headphones with active noise cancellation and 40h battery.",
                price: 349.95,
                category: .electronics,
                sku: "TECH-AUD-002",
                stockQuantity: 80,
                tags: ["audio", "bluetooth", "anc", "music"]
            ),
            Product(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "Mechanical Ergonomic Keyboard",
                description: "Split mechanical keyboard with hot-swappable switches and RGB backlight.",
                price: 169.50,
                category: .electronics,
                sku: "TECH-KEY-003",
                stockQuantity: 42,
                tags: ["keyboard", "mechanical", "ergonomic"]
            ),
            Product(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "Organic Single-Origin Coffee Beans",
                description: "Fair-trade specialty coffee beans roasted to medium perfection (1kg).",
                price: 28.00,
                category: .food,
                sku: "FOOD-COF-001",
                stockQuantity: 150,
                tags: ["coffee", "organic", "fair-trade"]
            ),
            Product(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                name: "Server-Side Swift in Action",
                description: "Comprehensive guide to building scalable backend APIs with Swift and Vapor.",
                price: 49.99,
                category: .books,
                sku: "BOOK-SWF-001",
                stockQuantity: 60,
                tags: ["swift", "vapor", "backend", "programming"]
            )
        ]

        var dict: [UUID: Product] = [:]
        for product in samples {
            dict[product.id] = product
        }
        return dict
    }

    // MARK: - CRUD Operations

    func list(params: ProductQueryParameters) -> (items: [Product], total: Int) {
        var result = Array(products.values)

        // Category filter
        if let category = params.category {
            result = result.filter { $0.category == category }
        }

        // Search filter (case-insensitive name, description, sku, tags)
        if let search = params.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            let lower = search.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower) ||
                $0.description.lowercased().contains(lower) ||
                $0.sku.lowercased().contains(lower) ||
                $0.tags.contains(where: { $0.lowercased().contains(lower) })
            }
        }

        // In-stock filter
        if let inStock = params.inStock {
            result = result.filter { inStock ? ($0.stockQuantity > 0) : ($0.stockQuantity == 0) }
        }

        // Min & Max Price filter
        if let minPrice = params.minPrice {
            result = result.filter { $0.price >= minPrice }
        }
        if let maxPrice = params.maxPrice {
            result = result.filter { $0.price <= maxPrice }
        }

        // Total count before pagination
        let total = result.count

        // Sorting
        let sort = params.sort?.lowercased() ?? "createdat"
        let isAsc = (params.order?.lowercased() ?? "asc") == "asc"

        result.sort { a, b in
            switch sort {
            case "name":
                return isAsc ? (a.name < b.name) : (a.name > b.name)
            case "price":
                return isAsc ? (a.price < b.price) : (a.price > b.price)
            case "stock":
                return isAsc ? (a.stockQuantity < b.stockQuantity) : (a.stockQuantity > b.stockQuantity)
            default: // createdAt
                return isAsc ? (a.createdAt < b.createdAt) : (a.createdAt > b.createdAt)
            }
        }

        // Pagination
        let page = max(1, params.page ?? 1)
        let per = max(1, min(100, params.per ?? 10))
        let startIndex = (page - 1) * per

        guard startIndex < result.count else {
            return ([], total)
        }

        let endIndex = min(startIndex + per, result.count)
        let pageItems = Array(result[startIndex..<endIndex])
        return (pageItems, total)
    }

    func get(id: UUID) -> Product? {
        products[id]
    }

    func create(dto: CreateProductDTO) -> Product {
        let product = Product(
            name: dto.name,
            description: dto.description,
            price: dto.price,
            category: dto.category,
            sku: dto.sku,
            stockQuantity: dto.stockQuantity,
            tags: dto.tags ?? []
        )
        products[product.id] = product
        broadcast(event: ProductEventNotification(
            eventType: .created,
            product: product,
            message: "Product '\(product.name)' was created"
        ))
        return product
    }

    func update(id: UUID, dto: UpdateProductDTO) -> Product? {
        guard var product = products[id] else { return nil }
        product.name = dto.name
        product.description = dto.description
        product.price = dto.price
        product.category = dto.category
        product.sku = dto.sku
        product.stockQuantity = dto.stockQuantity
        product.tags = dto.tags ?? product.tags
        product.updatedAt = Date()
        products[id] = product
        broadcast(event: ProductEventNotification(
            eventType: .updated,
            product: product,
            message: "Product '\(product.name)' was updated"
        ))
        return product
    }

    func patch(id: UUID, dto: PatchProductDTO) -> Product? {
        guard var product = products[id] else { return nil }
        if let name = dto.name { product.name = name }
        if let description = dto.description { product.description = description }
        if let price = dto.price {
            product.price = price
            broadcast(event: ProductEventNotification(
                eventType: .priceChanged,
                product: product,
                message: "Price for '\(product.name)' updated to $\(price)"
            ))
        }
        if let category = dto.category { product.category = category }
        if let sku = dto.sku { product.sku = sku }
        if let stockQuantity = dto.stockQuantity {
            product.stockQuantity = stockQuantity
            broadcast(event: ProductEventNotification(
                eventType: .stockChanged,
                product: product,
                message: "Stock for '\(product.name)' updated to \(stockQuantity)"
            ))
        }
        if let tags = dto.tags { product.tags = tags }
        product.updatedAt = Date()
        products[id] = product
        return product
    }

    func delete(id: UUID) -> Bool {
        guard let product = products.removeValue(forKey: id) else { return false }
        broadcast(event: ProductEventNotification(
            eventType: .deleted,
            productId: id,
            message: "Product '\(product.name)' (ID: \(id)) was deleted"
        ))
        return true
    }

    func adjustStock(id: UUID, delta: Int) -> (success: Bool, currentStock: Int, product: Product?) {
        guard var product = products[id] else {
            return (false, 0, nil)
        }
        let newStock = product.stockQuantity + delta
        if newStock < 0 {
            return (false, product.stockQuantity, product)
        }
        product.stockQuantity = newStock
        product.updatedAt = Date()
        products[id] = product
        broadcast(event: ProductEventNotification(
            eventType: .stockChanged,
            product: product,
            message: "Stock for '\(product.name)' adjusted by \(delta) (current: \(newStock))"
        ))
        return (true, newStock, product)
    }

    // MARK: - Pub/Sub Streaming

    func makeEventStream() -> AsyncStream<ProductEventNotification> {
        let listenerId = UUID()
        return AsyncStream { continuation in
            listeners[listenerId] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeListener(listenerId)
                }
            }
        }
    }

    private func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    private func broadcast(event: ProductEventNotification) {
        for continuation in listeners.values {
            continuation.yield(event)
        }
    }
}

// MARK: - Vapor Application Storage Key

struct ProductRepositoryKey: StorageKey {
    typealias Value = ProductRepository
}

extension Application {
    var productRepository: ProductRepository {
        get {
            guard let repo = storage[ProductRepositoryKey.self] else {
                fatalError("ProductRepository not initialized. Please call configure.")
            }
            return repo
        }
        set {
            storage[ProductRepositoryKey.self] = newValue
        }
    }
}
