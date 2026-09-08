import Vapor
import Foundation

// MARK: - Product Category
enum ProductCategory: String, Codable, Sendable, CaseIterable {
    case electronics
    case clothing
    case books
    case home
    case food
}

// MARK: - Product Model
struct Product: Content, Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var price: Double
    var category: ProductCategory
    var sku: String
    var stockQuantity: Int
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        price: Double,
        category: ProductCategory,
        sku: String,
        stockQuantity: Int,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.category = category
        self.sku = sku
        self.stockQuantity = stockQuantity
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - DTOs

struct CreateProductDTO: Content, Sendable, Validatable {
    let name: String
    let description: String
    let price: Double
    let category: ProductCategory
    let sku: String
    let stockQuantity: Int
    let tags: [String]?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty, required: true)
        validations.add("sku", as: String.self, is: !.empty, required: true)
        validations.add("price", as: Double.self, is: .range(0.01...), required: true)
        validations.add("stockQuantity", as: Int.self, is: .range(0...), required: true)
    }
}

struct UpdateProductDTO: Content, Sendable, Validatable {
    let name: String
    let description: String
    let price: Double
    let category: ProductCategory
    let sku: String
    let stockQuantity: Int
    let tags: [String]?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty, required: true)
        validations.add("sku", as: String.self, is: !.empty, required: true)
        validations.add("price", as: Double.self, is: .range(0.01...), required: true)
        validations.add("stockQuantity", as: Int.self, is: .range(0...), required: true)
    }
}

struct PatchProductDTO: Content, Sendable {
    let name: String?
    let description: String?
    let price: Double?
    let category: ProductCategory?
    let sku: String?
    let stockQuantity: Int?
    let tags: [String]?
}

struct ProductQueryParameters: Content, Sendable {
    let search: String?
    let category: ProductCategory?
    let inStock: Bool?
    let minPrice: Double?
    let maxPrice: Double?
    let page: Int?
    let per: Int?
    let sort: String?
    let order: String?
}

// MARK: - Generic Paginated Response

struct PaginatedResponse<T: Content & Sendable>: Content, Sendable {
    struct Metadata: Content, Sendable {
        let page: Int
        let per: Int
        let total: Int
        let totalPages: Int
    }

    let items: [T]
    let metadata: Metadata

    init(items: [T], page: Int, per: Int, total: Int) {
        self.items = items
        let totalPages = max(1, Int(ceil(Double(total) / Double(max(1, per)))))
        self.metadata = Metadata(page: page, per: per, total: total, totalPages: totalPages)
    }
}

// MARK: - Event Notification

enum ProductEventType: String, Codable, Sendable {
    case created
    case updated
    case deleted
    case stockChanged
    case priceChanged
}

struct ProductEventNotification: Content, Sendable {
    let eventType: ProductEventType
    let product: Product?
    let productId: UUID?
    let timestamp: Date
    let message: String

    init(
        eventType: ProductEventType,
        product: Product? = nil,
        productId: UUID? = nil,
        timestamp: Date = Date(),
        message: String
    ) {
        self.eventType = eventType
        self.product = product
        self.productId = productId ?? product?.id
        self.timestamp = timestamp
        self.message = message
    }
}

// MARK: - Diagnostic & Auth DTOs

struct StatusTestResponse: Content, Sendable {
    let statusCode: UInt
    let reasonPhrase: String
    let message: String
    let timestamp: Date
}

struct HeaderEchoResponse: Content, Sendable {
    let method: String
    let uri: String
    let headers: [String: String]
    let remoteAddress: String?
    let serverTime: Date
}

struct AuthTokenResponse: Content, Sendable {
    let token: String
    let tokenType: String
    let expiresIn: Int
    let username: String
    let roles: [String]
}

struct UserProfileResponse: Content, Sendable {
    let id: String
    let username: String
    let email: String
    let roles: [String]
    let permissions: [String]
    let authenticatedAt: Date
}

struct FileUploadResponse: Content, Sendable {
    let filename: String
    let contentType: String?
    let sizeInBytes: Int
    let sha256: String
    let message: String
}
