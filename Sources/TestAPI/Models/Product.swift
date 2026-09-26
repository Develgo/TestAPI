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

// MARK: - Dynamic JSON Value & Request Inspection Models

struct DynamicCodingKeys: CodingKey, Sendable {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            var dict: [String: JSONValue] = [:]
            for key in keyedContainer.allKeys {
                dict[key.stringValue] = try keyedContainer.decode(JSONValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !unkeyedContainer.isAtEnd {
                array.append(try unkeyedContainer.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let str):
            var container = encoder.singleValueContainer()
            try container.encode(str)
        case .number(let num):
            var container = encoder.singleValueContainer()
            try container.encode(num)
        case .int(let int):
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .object(let obj):
            var container = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (key, val) in obj {
                try container.encode(val, forKey: DynamicCodingKeys(stringValue: key))
            }
        case .array(let arr):
            var container = encoder.unkeyedContainer()
            for val in arr {
                try container.encode(val)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self {
            return dict[key]
        }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let arr) = self, index >= 0 && index < arr.count {
            return arr[index]
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let str) = self { return str }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

struct RequestBodyDetail: Content, Sendable {
    let raw: String?
    let json: JSONValue?
    let form: [String: String]?
    let sizeInBytes: Int
    let contentType: String?

    init(
        raw: String? = nil,
        json: JSONValue? = nil,
        form: [String: String]? = nil,
        sizeInBytes: Int = 0,
        contentType: String? = nil
    ) {
        self.raw = raw
        self.json = json
        self.form = form
        self.sizeInBytes = sizeInBytes
        self.contentType = contentType
    }
}

struct RequestDetailResponse: Content, Sendable {
    let method: String
    let uri: String
    let url: String
    let path: String
    let query: String?
    let queryParams: [String: String]
    let headers: [String: String]
    let body: RequestBodyDetail
    let remoteAddress: String?
    let serverTime: Date

    init(
        method: String,
        uri: String,
        url: String,
        path: String,
        query: String?,
        queryParams: [String: String],
        headers: [String: String],
        body: RequestBodyDetail,
        remoteAddress: String?,
        serverTime: Date = Date()
    ) {
        self.method = method
        self.uri = uri
        self.url = url
        self.path = path
        self.query = query
        self.queryParams = queryParams
        self.headers = headers
        self.body = body
        self.remoteAddress = remoteAddress
        self.serverTime = serverTime
    }
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
