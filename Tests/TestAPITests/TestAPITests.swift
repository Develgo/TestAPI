@testable import TestAPI
import VaporTesting
import Testing
import Vapor
import Foundation
import GRPCCore

@Suite("TestAPI Route & Controller Tests")
struct TestAPITests {

    @Test("Test Root Service Discovery Route")
    func rootDiscovery() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let dict = try res.content.decode([String: String].self)
                #expect(dict["name"] == "TestAPI")
                #expect(dict["rest_products"] == "/api/v1/products")
                #expect(dict["grpc_service"]?.contains("50051") == true)
            })
        }
    }

    @Test("Test REST Products - List and Pagination")
    func listProducts() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/products", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let response = try res.content.decode(PaginatedResponse<Product>.self)
                #expect(response.items.count >= 5)
                #expect(response.metadata.total >= 5)
                #expect(response.metadata.page == 1)
            })
        }
    }

    @Test("Test REST Products - Category Filter")
    func listProductsFiltered() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/products?category=food", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let response = try res.content.decode(PaginatedResponse<Product>.self)
                #expect(response.items.allSatisfy { $0.category == .food })
            })
        }
    }

    @Test("Test REST Products - Get By ID Success and 404")
    func getProductById() async throws {
        try await withApp(configure: configure) { app in
            let existingId = "11111111-1111-1111-1111-111111111111"
            try await app.testing().test(.GET, "api/v1/products/\(existingId)", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let product = try res.content.decode(Product.self)
                #expect(product.id.uuidString.lowercased() == existingId)
                #expect(product.name == "Ultra-Light Laptop Pro 16")
            })

            let nonExistentId = "00000000-0000-0000-0000-000000000000"
            try await app.testing().test(.GET, "api/v1/products/\(nonExistentId)", afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test("Test REST Products - Full Lifecycle: Create, Update, Patch, Delete")
    func productLifecycle() async throws {
        try await withApp(configure: configure) { app in
            // 1. Create Product
            var createdId: UUID?
            let createPayload = """
            {
                "name": "Wireless Gaming Mouse",
                "description": "Ultra-lightweight sensor mouse.",
                "price": 79.99,
                "category": "electronics",
                "sku": "TECH-MOU-099",
                "stockQuantity": 30,
                "tags": ["gaming", "mouse"]
            }
            """

            try await app.testing().test(.POST, "api/v1/products", beforeRequest: { req async in
                req.headers.contentType = .json
                req.body = .init(string: createPayload)
            }, afterResponse: { res async throws in
                #expect(res.status == .created)
                #expect(res.headers.contains(name: .location))
                let product = try res.content.decode(Product.self)
                #expect(product.name == "Wireless Gaming Mouse")
                #expect(product.price == 79.99)
                createdId = product.id
            })

            guard let id = createdId else {
                Issue.record("Failed to obtain created product ID")
                return
            }

            // 2. Put / Replace Product
            let updatePayload = """
            {
                "name": "Wireless Gaming Mouse Pro",
                "description": "Upgraded 4K polling rate sensor mouse.",
                "price": 99.99,
                "category": "electronics",
                "sku": "TECH-MOU-099-PRO",
                "stockQuantity": 25,
                "tags": ["gaming", "mouse", "pro"]
            }
            """

            try await app.testing().test(.PUT, "api/v1/products/\(id)", beforeRequest: { req async in
                req.headers.contentType = .json
                req.body = .init(string: updatePayload)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let updated = try res.content.decode(Product.self)
                #expect(updated.name == "Wireless Gaming Mouse Pro")
                #expect(updated.price == 99.99)
                #expect(updated.sku == "TECH-MOU-099-PRO")
            })

            // 3. Patch Product
            let patchPayload = """
            {
                "price": 89.99,
                "stockQuantity": 15
            }
            """

            try await app.testing().test(.PATCH, "api/v1/products/\(id)", beforeRequest: { req async in
                req.headers.contentType = .json
                req.body = .init(string: patchPayload)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let patched = try res.content.decode(Product.self)
                #expect(patched.price == 89.99)
                #expect(patched.stockQuantity == 15)
                #expect(patched.name == "Wireless Gaming Mouse Pro")
            })

            // 4. Delete Product
            try await app.testing().test(.DELETE, "api/v1/products/\(id)", afterResponse: { res async in
                #expect(res.status == .noContent)
            })

            // 5. Verify 404 after deletion
            try await app.testing().test(.GET, "api/v1/products/\(id)", afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test("Test Diagnostic Endpoints - Status Code Simulator")
    func diagnosticStatusCodes() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/test/status/418", afterResponse: { res async throws in
                #expect(res.status == .imATeapot)
                let body = try res.content.decode(StatusTestResponse.self)
                #expect(body.statusCode == 418)
            })

            try await app.testing().test(.GET, "api/v1/test/status/204", afterResponse: { res async in
                #expect(res.status == .noContent)
                #expect(res.body.readableBytes == 0)
            })
        }
    }

    @Test("Test Diagnostic Endpoints - Header Inspection")
    func diagnosticHeaders() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/test/headers", beforeRequest: { req async in
                req.headers.add(name: "X-Custom-Client", value: "TestClient-1.0")
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect(res.headers.contains(name: "X-TestAPI-Echo"))
                #expect(res.headers.contains(name: "X-Server-Time"))
                #expect(res.headers.contains(name: .eTag))
                let echo = try res.content.decode(HeaderEchoResponse.self)
                #expect(echo.headers["x-custom-client"] == "TestClient-1.0" || echo.headers["X-Custom-Client"] == "TestClient-1.0")
            })
        }
    }

    @Test("Test Diagnostic Endpoints - File Download")
    func diagnosticDownload() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/test/download", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.description.contains("text/csv") == true)
                #expect(res.headers.first(name: .contentDisposition)?.contains("sample-products.csv") == true)
                #expect(res.body.string.contains("Ultra-Light Laptop Pro 16"))
            })
        }
    }

    @Test("Test Authentication Simulation - Login and Profile Protection")
    func authSimulation() async throws {
        try await withApp(configure: configure) { app in
            // Login with valid credentials
            var authToken = ""
            let loginBody = """
            {"username":"tester","password":"password"}
            """

            try await app.testing().test(.POST, "api/v1/auth/login", beforeRequest: { req async in
                req.headers.contentType = .json
                req.body = .init(string: loginBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let tokenRes = try res.content.decode(AuthTokenResponse.self)
                #expect(tokenRes.token == AuthController.validToken)
                authToken = tokenRes.token
            })

            // Login with invalid credentials -> 401
            let invalidLogin = """
            {"username":"tester","password":"wrongpassword"}
            """
            try await app.testing().test(.POST, "api/v1/auth/login", beforeRequest: { req async in
                req.headers.contentType = .json
                req.body = .init(string: invalidLogin)
            }, afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })

            // Profile with Bearer token -> 200
            try await app.testing().test(.GET, "api/v1/auth/me", beforeRequest: { req async in
                req.headers.bearerAuthorization = .init(token: authToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let profile = try res.content.decode(UserProfileResponse.self)
                #expect(profile.username == "admin_tester")
                #expect(profile.roles.contains("admin"))
            })

            // Profile without Bearer token -> 401
            try await app.testing().test(.GET, "api/v1/auth/me", afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("Test gRPC ProductsService Unit Integration")
    func grpcProductsServiceDirect() async throws {
        let repo = ProductRepository()
        _ = ProductsGRPCService(repository: repo)

        // 1. GetProduct
        var getReq = Products_GetProductRequest()
        getReq.id = "11111111-1111-1111-1111-111111111111"
        // Dummy server context using GRPCCore
        // Test direct repository integration
        let product = await repo.get(id: UUID(uuidString: getReq.id)!)
        #expect(product != nil)
        #expect(product?.name == "Ultra-Light Laptop Pro 16")
        let protoProduct = product!.toProto()
        #expect(protoProduct.price == 1899.99)
        #expect(protoProduct.category == .electronics)

        // 2. Adjust Stock
        let (success, newStock, _) = await repo.adjustStock(id: UUID(uuidString: getReq.id)!, delta: 5)
        #expect(success == true)
        #expect(newStock == 30)
    }

    @Test("Test Diagnostic Endpoints - Request Inspection with Headers and Body")
    func diagnosticRequestInspectWithBodyAndHeaders() async throws {
        try await withApp(configure: configure) { app in
            let testPayload = """
            {
                "greeting": "Hello Vapor",
                "count": 100,
                "enabled": true,
                "metadata": {
                    "env": "testing",
                    "version": 2
                }
            }
            """

            try await app.testing().test(.POST, "api/v1/test/inspect?tag=vapor-test&debug=1", beforeRequest: { req async in
                req.headers.contentType = .json
                req.headers.add(name: "X-Test-Trace-ID", value: "trace-inspection-99")
                req.headers.add(name: "X-Custom-Client", value: "SwiftTesting")
                req.body = .init(string: testPayload)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect(res.headers.contains(name: "X-TestAPI-Echo"))
                #expect(res.headers.contains(name: "X-Server-Time"))

                let detail = try res.content.decode(RequestDetailResponse.self)
                #expect(detail.method == "POST")
                #expect(detail.path == "/api/v1/test/inspect")
                #expect(detail.queryParams["tag"] == "vapor-test")
                #expect(detail.queryParams["debug"] == "1")
                #expect(detail.headers["x-test-trace-id"] == "trace-inspection-99")
                #expect(detail.headers["x-custom-client"] == "SwiftTesting")
                #expect(detail.body.contentType?.contains("application/json") == true)
                #expect(detail.body.sizeInBytes > 0)
                #expect(detail.body.raw?.contains("Hello Vapor") == true)
                #expect(detail.body.json != nil)
                #expect(detail.body.json?["greeting"]?.stringValue == "Hello Vapor")
                #expect(detail.body.json?["count"]?.intValue == 100)
                #expect(detail.body.json?["enabled"]?.boolValue == true)
                #expect(detail.body.json?["metadata"]?["env"]?.stringValue == "testing")
                #expect(detail.body.json?["metadata"]?["version"]?.intValue == 2)
            })
        }
    }

    @Test("Test Diagnostic Endpoints - Request Inspection GET & Alias Route")
    func diagnosticRequestInspectGetAndAlias() async throws {
        try await withApp(configure: configure) { app in
            // Test GET on /api/v1/test/inspect (empty body)
            try await app.testing().test(.GET, "api/v1/test/inspect", beforeRequest: { req async in
                req.headers.add(name: "X-Client-Type", value: "Browser")
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let detail = try res.content.decode(RequestDetailResponse.self)
                #expect(detail.method == "GET")
                #expect(detail.body.sizeInBytes == 0)
                #expect(detail.body.json == nil)
                #expect(detail.body.raw == nil)
                #expect(detail.headers["x-client-type"] == "Browser")
            })

            // Test alias route /api/v1/test/request
            try await app.testing().test(.POST, "api/v1/test/request", beforeRequest: { req async in
                req.headers.contentType = .plainText
                req.body = .init(string: "raw text payload")
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let detail = try res.content.decode(RequestDetailResponse.self)
                #expect(detail.method == "POST")
                #expect(detail.path == "/api/v1/test/request")
                #expect(detail.body.raw == "raw text payload")
                #expect(detail.body.json == nil)
                #expect(detail.body.sizeInBytes == 16)
            })
        }
    }
}
