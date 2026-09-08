import Vapor
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import Logging

private actor GRPCServerRunner {
    private var serverTask: Task<Void, Never>?

    func start(host: String, port: Int, repository: ProductRepository, logger: Logger) {
        let grpcService = ProductsGRPCService(repository: repository)
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: host, port: port),
            transportSecurity: .plaintext
        )
        let server = GRPCServer(
            transport: transport,
            services: [grpcService]
        )

        logger.info("🚀 gRPC server listening on \(host):\(port)")

        serverTask = Task {
            do {
                try await server.serve()
            } catch is CancellationError {
                logger.info("gRPC server task was cancelled.")
            } catch {
                logger.error("gRPC server error: \(error)")
            }
        }
    }

    func stop(logger: Logger) async {
        logger.info("Shutting down gRPC server...")
        serverTask?.cancel()
        _ = await serverTask?.result
        serverTask = nil
    }
}

final class GRPCServerLifecycle: LifecycleHandler, Sendable {
    private let host: String
    private let port: Int
    private let repository: ProductRepository
    private let runner = GRPCServerRunner()

    init(host: String = "0.0.0.0", port: Int = 50051, repository: ProductRepository) {
        self.host = host
        self.port = port
        self.repository = repository
    }

    func didBootAsync(_ app: Application) async throws {
        await runner.start(host: host, port: port, repository: repository, logger: app.logger)
    }

    func shutdownAsync(_ app: Application) async {
        await runner.stop(logger: app.logger)
    }
}
