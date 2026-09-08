import GRPCCore
import GRPCProtobuf
import Foundation

// MARK: - Model to Proto Extensions

extension Product {
    func toProto() -> Products_ProductMessage {
        var msg = Products_ProductMessage()
        msg.id = id.uuidString
        msg.name = name
        msg.description_p = description
        msg.price = price
        msg.sku = sku
        msg.stockQuantity = Int32(stockQuantity)
        msg.tags = tags
        msg.createdAt = ISO8601DateFormatter().string(from: createdAt)
        msg.updatedAt = ISO8601DateFormatter().string(from: updatedAt)

        switch category {
        case .electronics: msg.category = .electronics
        case .clothing: msg.category = .clothing
        case .books: msg.category = .books
        case .home: msg.category = .home
        case .food: msg.category = .food
        }
        return msg
    }
}

extension Products_ProductCategory {
    func toModel() -> ProductCategory? {
        switch self {
        case .electronics: return .electronics
        case .clothing: return .clothing
        case .books: return .books
        case .home: return .home
        case .food: return .food
        case .categoryUnspecified, .UNRECOGNIZED: return nil
        }
    }
}

// MARK: - ProductsGRPCService Implementation

@available(macOS 15.0, *)
struct ProductsGRPCService: Products_ProductsService.SimpleServiceProtocol, Sendable {
    private let repository: ProductRepository

    init(repository: ProductRepository) {
        self.repository = repository
    }

    // 1. Unary RPC: GetProduct
    func getProduct(
        request: Products_GetProductRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Products_ProductMessage {
        guard let uuid = UUID(uuidString: request.id) else {
            throw RPCError(code: .invalidArgument, message: "Invalid product UUID: '\(request.id)'")
        }
        guard let product = await repository.get(id: uuid) else {
            throw RPCError(code: .notFound, message: "Product with ID '\(request.id)' was not found.")
        }
        return product.toProto()
    }

    // 2. Unary RPC: ListProducts
    func listProducts(
        request: Products_ListProductsRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Products_ListProductsResponse {
        let queryParams = ProductQueryParameters(
            search: request.search.isEmpty ? nil : request.search,
            category: request.category.toModel(),
            inStock: nil,
            minPrice: nil,
            maxPrice: nil,
            page: request.page > 0 ? Int(request.page) : 1,
            per: request.perPage > 0 ? Int(request.perPage) : 10,
            sort: "name",
            order: "asc"
        )

        let (items, total) = await repository.list(params: queryParams)

        var response = Products_ListProductsResponse()
        response.products = items.map { $0.toProto() }
        response.total = Int32(total)
        response.page = Int32(queryParams.page ?? 1)
        response.perPage = Int32(queryParams.per ?? 10)
        response.totalPages = Int32(max(1, Int(ceil(Double(total) / Double(max(1, queryParams.per ?? 10))))))
        return response
    }

    // 3. Unary RPC: CreateProduct
    func createProduct(
        request: Products_CreateProductRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Products_ProductMessage {
        guard !request.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RPCError(code: .invalidArgument, message: "Product name cannot be empty.")
        }
        guard request.price > 0 else {
            throw RPCError(code: .invalidArgument, message: "Product price must be greater than zero.")
        }
        guard let category = request.category.toModel() else {
            throw RPCError(code: .invalidArgument, message: "A valid product category is required.")
        }

        let sku = request.sku.isEmpty ? "PROD-\(UUID().uuidString.prefix(6))" : request.sku
        let dto = CreateProductDTO(
            name: request.name,
            description: request.description_p,
            price: request.price,
            category: category,
            sku: sku,
            stockQuantity: max(0, Int(request.stockQuantity)),
            tags: request.tags
        )

        let product = await repository.create(dto: dto)
        return product.toProto()
    }

    // 4. Server Streaming RPC: StreamProductEvents
    func streamProductEvents(
        request: Products_StreamEventsRequest,
        response: GRPCCore.RPCWriter<Products_ProductEvent>,
        context: GRPCCore.ServerContext
    ) async throws {
        let eventStream = await repository.makeEventStream()
        for await event in eventStream {
            // Apply category filter if requested
            if !request.filterCategory.isEmpty && event.product?.category.rawValue != request.filterCategory {
                continue
            }

            var protoEvent = Products_ProductEvent()
            switch event.eventType {
            case .created: protoEvent.eventType = .created
            case .updated: protoEvent.eventType = .updated
            case .deleted: protoEvent.eventType = .deleted
            case .stockChanged: protoEvent.eventType = .stockUpdated
            case .priceChanged: protoEvent.eventType = .priceChanged
            }

            if let p = event.product {
                protoEvent.product = p.toProto()
            }
            protoEvent.timestamp = ISO8601DateFormatter().string(from: event.timestamp)
            protoEvent.message = event.message

            try await response.write(protoEvent)
        }
    }

    // 5. Client Streaming RPC: BatchCreateProducts
    func batchCreateProducts(
        request: GRPCCore.RPCAsyncSequence<Products_CreateProductRequest, any Swift.Error>,
        context: GRPCCore.ServerContext
    ) async throws -> Products_BatchCreateResponse {
        var createdIds: [String] = []

        for try await item in request {
            guard let category = item.category.toModel() else {
                continue
            }
            let sku = item.sku.isEmpty ? "PROD-\(UUID().uuidString.prefix(6))" : item.sku
            let dto = CreateProductDTO(
                name: item.name,
                description: item.description_p,
                price: item.price,
                category: category,
                sku: sku,
                stockQuantity: max(0, Int(item.stockQuantity)),
                tags: item.tags
            )
            let product = await repository.create(dto: dto)
            createdIds.append(product.id.uuidString)
        }

        var batchResponse = Products_BatchCreateResponse()
        batchResponse.createdCount = Int32(createdIds.count)
        batchResponse.createdIds = createdIds
        batchResponse.summary = "Successfully created \(createdIds.count) products via client streaming."
        return batchResponse
    }

    // 6. Bidirectional Streaming RPC: LiveInventorySync
    func liveInventorySync(
        request: GRPCCore.RPCAsyncSequence<Products_InventoryUpdateRequest, any Swift.Error>,
        response: GRPCCore.RPCWriter<Products_InventoryUpdateResponse>,
        context: GRPCCore.ServerContext
    ) async throws {
        for try await update in request {
            var updateResp = Products_InventoryUpdateResponse()
            updateResp.productID = update.productID
            updateResp.timestamp = ISO8601DateFormatter().string(from: Date())

            guard let uuid = UUID(uuidString: update.productID) else {
                updateResp.success = false
                updateResp.message = "Invalid product UUID: '\(update.productID)'"
                try await response.write(updateResp)
                continue
            }

            let (success, currentStock, product) = await repository.adjustStock(id: uuid, delta: Int(update.quantityDelta))
            updateResp.success = success
            updateResp.currentStock = Int32(currentStock)
            if success {
                updateResp.message = "Updated stock for '\(product?.name ?? "product")' to \(currentStock)"
            } else {
                updateResp.message = "Failed to adjust stock for product \(update.productID) (insufficient inventory or not found)"
            }

            try await response.write(updateResp)
        }
    }
}
