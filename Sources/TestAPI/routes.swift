import Vapor

func routes(_ app: Application) throws {
    // Root service directory endpoint
    app.get { req async -> [String: String] in
        [
            "name": "TestAPI",
            "version": "1.0.0",
            "status": "online",
            "rest_products": "/api/v1/products",
            "rest_diagnostics": "/api/v1/test",
            "rest_inspect": "/api/v1/test/inspect",
            "rest_auth": "/api/v1/auth",
            "ws_echo": "/ws/echo",
            "ws_ticker": "/ws/ticker",
            "ws_chat": "/ws/chat",
            "grpc_service": "products.ProductsService on port 50051"
        ]
    }

    // Register route controllers
    try app.register(collection: ProductController())
    try app.register(collection: DiagnosticController())
    try app.register(collection: AuthController())
    try app.register(collection: WebSocketController())
}
