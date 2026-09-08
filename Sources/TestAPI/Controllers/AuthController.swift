import Vapor

struct AuthController: RouteCollection, Sendable {
    static let validToken = "test-bearer-token-abc123xyz"

    init() {}

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("api", "v1", "auth")
        auth.post("login", use: login)
        auth.get("me", use: profile)
    }

    struct LoginDTO: Content {
        let username: String
        let password: String
    }

    // POST /api/v1/auth/login
    @Sendable
    func login(req: Request) async throws -> AuthTokenResponse {
        let credentials = try req.content.decode(LoginDTO.self)
        guard !credentials.username.isEmpty && !credentials.password.isEmpty else {
            throw Abort(.badRequest, reason: "Username and password are required.")
        }

        // Mock authentication check
        guard credentials.password == "password" || credentials.password == "admin123" else {
            throw Abort(.unauthorized, reason: "Invalid username or password.")
        }

        return AuthTokenResponse(
            token: Self.validToken,
            tokenType: "Bearer",
            expiresIn: 3600,
            username: credentials.username,
            roles: ["admin", "tester"]
        )
    }

    // GET /api/v1/auth/me
    @Sendable
    func profile(req: Request) async throws -> UserProfileResponse {
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing Authorization Bearer header.")
        }

        guard bearer.token == Self.validToken else {
            throw Abort(.unauthorized, reason: "Invalid or expired Bearer token.")
        }

        return UserProfileResponse(
            id: "user-1001",
            username: "admin_tester",
            email: "tester@example.com",
            roles: ["admin", "tester"],
            permissions: ["read:products", "write:products", "admin:all"],
            authenticatedAt: Date()
        )
    }
}
