import Vapor

struct ProductController: RouteCollection, Sendable {
    init() {}

    func boot(routes: any RoutesBuilder) throws {
        let products = routes.grouped("api", "v1", "products")
        products.get(use: index)
        products.post(use: create)

        let product = products.grouped(":id")
        product.get(use: getById)
        product.put(use: update)
        product.patch(use: patch)
        product.delete(use: delete)
    }

    // GET /api/v1/products
    @Sendable
    func index(req: Request) async throws -> PaginatedResponse<Product> {
        let queryParams = try req.query.decode(ProductQueryParameters.self)
        let repo = req.application.productRepository
        let (items, total) = await repo.list(params: queryParams)
        let page = max(1, queryParams.page ?? 1)
        let per = max(1, min(100, queryParams.per ?? 10))
        return PaginatedResponse(items: items, page: page, per: per, total: total)
    }

    // GET /api/v1/products/:id
    @Sendable
    func getById(req: Request) async throws -> Product {
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid product UUID parameter.")
        }
        let repo = req.application.productRepository
        guard let product = await repo.get(id: id) else {
            throw Abort(.notFound, reason: "Product with ID '\(id)' not found.")
        }
        return product
    }

    // POST /api/v1/products
    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateProductDTO.validate(content: req)
        let dto = try req.content.decode(CreateProductDTO.self)
        let repo = req.application.productRepository
        let product = await repo.create(dto: dto)

        let response = Response(status: .created)
        try response.content.encode(product)
        response.headers.replaceOrAdd(name: .location, value: "/api/v1/products/\(product.id)")
        return response
    }

    // PUT /api/v1/products/:id
    @Sendable
    func update(req: Request) async throws -> Product {
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid product UUID parameter.")
        }
        try UpdateProductDTO.validate(content: req)
        let dto = try req.content.decode(UpdateProductDTO.self)
        let repo = req.application.productRepository
        guard let updated = await repo.update(id: id, dto: dto) else {
            throw Abort(.notFound, reason: "Product with ID '\(id)' not found to update.")
        }
        return updated
    }

    // PATCH /api/v1/products/:id
    @Sendable
    func patch(req: Request) async throws -> Product {
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid product UUID parameter.")
        }
        let dto = try req.content.decode(PatchProductDTO.self)
        let repo = req.application.productRepository
        guard let updated = await repo.patch(id: id, dto: dto) else {
            throw Abort(.notFound, reason: "Product with ID '\(id)' not found to patch.")
        }
        return updated
    }

    // DELETE /api/v1/products/:id
    @Sendable
    func delete(req: Request) async throws -> Response {
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid product UUID parameter.")
        }
        let repo = req.application.productRepository
        guard await repo.delete(id: id) else {
            throw Abort(.notFound, reason: "Product with ID '\(id)' not found to delete.")
        }
        return Response(status: .noContent)
    }
}
