import Vapor

/// configures your application
func configure(_ app: Application) async throws {
    // Initialize shared in-memory ProductRepository
    let repository = ProductRepository()
    app.productRepository = repository

    // Initialize shared ChatRoom for WebSockets
    app.chatRoom = ChatRoom()

    // Register gRPC lifecycle handler (runs concurrently on port 50051 or GRPC_PORT)
    let grpcPort = Environment.get("GRPC_PORT").flatMap(Int.init) ?? 50051
    let grpcHost = Environment.get("GRPC_HOST") ?? "0.0.0.0"
    app.lifecycle.use(GRPCServerLifecycle(host: grpcHost, port: grpcPort, repository: repository))

    // Register routes
    try routes(app)
}
