import Vapor
import Crypto
import Foundation

struct DiagnosticController: RouteCollection, Sendable {
    init() {}

    func boot(routes: any RoutesBuilder) throws {
        let test = routes.grouped("api", "v1", "test")
        test.get("status", ":code", use: testStatus)
        test.get("delay", use: testDelay)
        test.get("headers", use: testHeaders)
        test.post("headers", use: testHeaders)
        test.post("upload", use: testUpload)
        test.get("download", use: testDownload)

        // Request inspection routes (headers, body, method, query, etc.)
        test.on(.GET, "inspect", use: testInspectRequest)
        test.on(.POST, "inspect", use: testInspectRequest)
        test.on(.PUT, "inspect", use: testInspectRequest)
        test.on(.PATCH, "inspect", use: testInspectRequest)
        test.on(.DELETE, "inspect", use: testInspectRequest)

        // Alias under "request"
        test.on(.GET, "request", use: testInspectRequest)
        test.on(.POST, "request", use: testInspectRequest)
        test.on(.PUT, "request", use: testInspectRequest)
        test.on(.PATCH, "request", use: testInspectRequest)
        test.on(.DELETE, "request", use: testInspectRequest)
    }

    // GET /api/v1/test/status/:code
    @Sendable
    func testStatus(req: Request) async throws -> Response {
        guard let codeString = req.parameters.get("code"), let code = UInt(codeString) else {
            throw Abort(.badRequest, reason: "Status code must be a valid positive integer.")
        }
        let status = HTTPResponseStatus(statusCode: Int(code))
        if status == .noContent {
            return Response(status: .noContent)
        }

        let body = StatusTestResponse(
            statusCode: code,
            reasonPhrase: status.reasonPhrase,
            message: "Simulated response for HTTP status \(code)",
            timestamp: Date()
        )
        let res = Response(status: status)
        try res.content.encode(body)
        return res
    }

    // GET /api/v1/test/delay?seconds=2
    @Sendable
    func testDelay(req: Request) async throws -> Response {
        struct DelayQuery: Content {
            let seconds: Double?
        }
        let query = try? req.query.decode(DelayQuery.self)
        let requested = query?.seconds ?? 1.0
        let seconds = max(0.0, min(10.0, requested))

        let start = Date()
        let nanos = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
        let elapsed = Date().timeIntervalSince(start)

        struct DelayResponse: Content {
            let requestedSeconds: Double
            let actualElapsedSeconds: Double
            let message: String
        }

        let response = DelayResponse(
            requestedSeconds: seconds,
            actualElapsedSeconds: elapsed,
            message: "Successfully delayed response by \(seconds)s"
        )
        let res = Response(status: .ok)
        try res.content.encode(response)
        return res
    }

    // GET & POST /api/v1/test/headers
    @Sendable
    func testHeaders(req: Request) async throws -> Response {
        var headerDict: [String: String] = [:]
        for (name, value) in req.headers {
            headerDict[name] = value
        }

        let body = HeaderEchoResponse(
            method: req.method.rawValue,
            uri: req.url.string,
            headers: headerDict,
            remoteAddress: req.remoteAddress?.description,
            serverTime: Date()
        )

        let res = Response(status: .ok)
        try res.content.encode(body)
        res.headers.replaceOrAdd(name: "X-TestAPI-Echo", value: "Enabled")
        res.headers.replaceOrAdd(name: "X-Server-Time", value: ISO8601DateFormatter().string(from: Date()))
        res.headers.replaceOrAdd(name: .eTag, value: "\"test-api-etag-\(abs(body.method.hashValue))\"")
        return res
    }

    // POST /api/v1/test/upload
    @Sendable
    func testUpload(req: Request) async throws -> FileUploadResponse {
        struct UploadForm: Content {
            let file: File?
        }

        if let form = try? req.content.decode(UploadForm.self), let file = form.file {
            let data = Data(file.data.readableBytesView)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            return FileUploadResponse(
                filename: file.filename,
                contentType: file.extension != nil ? HTTPMediaType.fileExtension(file.extension!)?.description : "application/octet-stream",
                sizeInBytes: data.count,
                sha256: hash,
                message: "Multipart file uploaded successfully."
            )
        }

        // Fallback to raw body
        if let bodyBuffer = req.body.data {
            let data = Data(bodyBuffer.readableBytesView)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            return FileUploadResponse(
                filename: "raw_payload.bin",
                contentType: req.headers.contentType?.description ?? "application/octet-stream",
                sizeInBytes: data.count,
                sha256: hash,
                message: "Raw body payload uploaded successfully."
            )
        }

        throw Abort(.badRequest, reason: "No file or body payload provided.")
    }

    // GET /api/v1/test/download
    @Sendable
    func testDownload(req: Request) async throws -> Response {
        let csvContent = """
        id,name,price,category,stock
        11111111-1111-1111-1111-111111111111,Ultra-Light Laptop Pro 16,1899.99,electronics,25
        22222222-2222-2222-2222-222222222222,Wireless Noise-Cancelling Headphones,349.95,electronics,80
        33333333-3333-3333-3333-333333333333,Mechanical Ergonomic Keyboard,169.50,electronics,42
        44444444-4444-4444-4444-444444444444,Organic Single-Origin Coffee Beans,28.00,food,150
        55555555-5555-5555-5555-555555555555,Server-Side Swift in Action,49.99,books,60
        """

        let res = Response(status: .ok)
        res.body = .init(string: csvContent)
        res.headers.replaceOrAdd(name: .contentType, value: "text/csv; charset=utf-8")
        res.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"sample-products.csv\"")
        return res
    }

    // ANY /api/v1/test/inspect & /api/v1/test/request
    @Sendable
    func testInspectRequest(req: Request) async throws -> Response {
        var headerDict: [String: String] = [:]
        for (name, value) in req.headers {
            if let existing = headerDict[name] {
                headerDict[name] = "\(existing), \(value)"
            } else {
                headerDict[name] = value
            }
            let lower = name.lowercased()
            if headerDict[lower] == nil {
                headerDict[lower] = value
            }
        }

        var queryParams: [String: String] = [:]
        if let query = req.url.query {
            let pairs = query.split(separator: "&")
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                    let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    queryParams[key] = value
                } else if parts.count == 1 {
                    let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                    queryParams[key] = ""
                }
            }
        }

        var rawBody: String? = nil
        var jsonBody: JSONValue? = nil
        var formBody: [String: String]? = nil
        let sizeInBytes: Int

        if let bodyBuffer = req.body.data {
            sizeInBytes = bodyBuffer.readableBytes
            if sizeInBytes > 0 {
                if let str = bodyBuffer.getString(at: bodyBuffer.readerIndex, length: sizeInBytes) {
                    rawBody = str
                }
                let data = Data(bodyBuffer.readableBytesView)
                if let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    jsonBody = parsed
                }
                if let contentType = req.headers.contentType, contentType == .urlEncodedForm, let rawStr = rawBody {
                    var parsedForm: [String: String] = [:]
                    let pairs = rawStr.split(separator: "&")
                    for pair in pairs {
                        let parts = pair.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 {
                            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[0])
                            let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[1])
                            parsedForm[key] = value
                        } else if parts.count == 1 {
                            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[0])
                            parsedForm[key] = ""
                        }
                    }
                    if !parsedForm.isEmpty {
                        formBody = parsedForm
                    }
                }
            }
        } else {
            sizeInBytes = 0
        }

        let bodyDetail = RequestBodyDetail(
            raw: rawBody,
            json: jsonBody,
            form: formBody,
            sizeInBytes: sizeInBytes,
            contentType: req.headers.contentType?.description
        )

        let detail = RequestDetailResponse(
            method: req.method.rawValue,
            uri: req.url.string,
            url: req.url.string,
            path: req.url.path,
            query: req.url.query,
            queryParams: queryParams,
            headers: headerDict,
            body: bodyDetail,
            remoteAddress: req.remoteAddress?.description,
            serverTime: Date()
        )

        let res = Response(status: .ok)
        try res.content.encode(detail)
        res.headers.replaceOrAdd(name: "X-TestAPI-Echo", value: "Enabled")
        res.headers.replaceOrAdd(name: "X-Server-Time", value: ISO8601DateFormatter().string(from: Date()))
        return res
    }
}
