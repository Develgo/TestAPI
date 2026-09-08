import Vapor
import Foundation

// MARK: - Thread-safe Chat Room Actor

actor ChatRoom {
    private var clients: [UUID: WebSocket] = [:]
    private var usernames: [UUID: String] = [:]

    init() {}

    func add(id: UUID, socket: WebSocket) {
        clients[id] = socket
    }

    func remove(id: UUID) {
        let username = usernames.removeValue(forKey: id) ?? "Anonymous"
        clients.removeValue(forKey: id)
        broadcast(message: """
        {"type":"user_left","username":"\(username)","onlineCount":\(clients.count)}
        """)
    }

    func setUsername(id: UUID, username: String) {
        usernames[id] = username
        broadcast(message: """
        {"type":"user_joined","username":"\(username)","onlineCount":\(clients.count)}
        """)
    }

    func broadcastChat(id: UUID, text: String) {
        let username = usernames[id] ?? "Anonymous"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        broadcast(message: """
        {"type":"chat_message","username":"\(username)","text":"\(escapedText)","timestamp":"\(timestamp)"}
        """)
    }

    private func broadcast(message: String) {
        for socket in clients.values {
            socket.send(message, promise: nil)
        }
    }
}

// MARK: - Storage Key for ChatRoom

struct ChatRoomKey: StorageKey {
    typealias Value = ChatRoom
}

extension Application {
    var chatRoom: ChatRoom {
        get {
            guard let room = storage[ChatRoomKey.self] else {
                fatalError("ChatRoom not initialized.")
            }
            return room
        }
        set {
            storage[ChatRoomKey.self] = newValue
        }
    }
}

// MARK: - WebSocket Controller

struct WebSocketController: RouteCollection, Sendable {
    init() {}

    func boot(routes: any RoutesBuilder) throws {
        let ws = routes.grouped("ws")
        ws.webSocket("echo", onUpgrade: handleEcho)
        ws.webSocket("ticker", onUpgrade: handleTicker)
        ws.webSocket("chat", onUpgrade: handleChat)
    }

    // MARK: - /ws/echo
    @Sendable
    func handleEcho(req: Request, ws: WebSocket) {
        ws.onText { socket, text in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let response = """
            {"type":"echo","received":"\(escaped)","length":\(text.count),"timestamp":"\(timestamp)"}
            """
            socket.send(response, promise: nil)
        }

        ws.onBinary { socket, buffer in
            socket.send(buffer, promise: nil)
        }
    }

    // MARK: - /ws/ticker
    @Sendable
    func handleTicker(req: Request, ws: WebSocket) {
        let repo = req.application.productRepository

        // Send welcome message
        ws.send("""
        {"type":"welcome","channel":"ticker","intervalSeconds":2,"message":"Connected to live product & price ticker"}
        """, promise: nil)

        // Task 1: Periodic price ticker
        let tickerTask = Task {
            let symbols = ["TECH-LAP-001", "TECH-AUD-002", "TECH-KEY-003", "FOOD-COF-001", "BOOK-SWF-001"]
            var basePrices: [String: Double] = [
                "TECH-LAP-001": 1899.99,
                "TECH-AUD-002": 349.95,
                "TECH-KEY-003": 169.50,
                "FOOD-COF-001": 28.00,
                "BOOK-SWF-001": 49.99
            ]

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }

                let symbol = symbols.randomElement() ?? "TECH-LAP-001"
                let current = basePrices[symbol] ?? 100.0
                let delta = Double.random(in: -2.5...2.5)
                let newPrice = max(1.0, (current + delta * 100).rounded() / 100)
                basePrices[symbol] = newPrice

                let timestamp = ISO8601DateFormatter().string(from: Date())
                let msg = """
                {"type":"ticker","symbol":"\(symbol)","price":\(newPrice),"change":\(Double(String(format: "%.2f", delta)) ?? 0.0),"timestamp":"\(timestamp)"}
                """
                ws.send(msg, promise: nil)
            }
        }

        // Task 2: Listen for real repository events (created, updated, deleted)
        let eventTask = Task {
            let eventStream = await repo.makeEventStream()
            for await event in eventStream {
                guard !Task.isCancelled else { break }
                if let jsonData = try? JSONEncoder().encode(event),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    ws.send(jsonString, promise: nil)
                }
            }
        }

        ws.onClose.whenComplete { _ in
            tickerTask.cancel()
            eventTask.cancel()
        }
    }

    // MARK: - /ws/chat
    @Sendable
    func handleChat(req: Request, ws: WebSocket) {
        let room = req.application.chatRoom
        let clientId = UUID()
        Task {
            await room.add(id: clientId, socket: ws)
        }

        ws.send("""
        {"type":"welcome","clientId":"\(clientId)","message":"Send JSON: {\\"action\\":\\"join\\", \\"username\\":\\"Name\\"} or {\\"action\\":\\"message\\", \\"text\\":\\"Hello\\"}"}
        """, promise: nil)

        struct ChatAction: Decodable {
            let action: String
            let username: String?
            let text: String?
        }

        ws.onText { _, text in
            guard let data = text.data(using: .utf8),
                  let action = try? JSONDecoder().decode(ChatAction.self, from: data) else {
                ws.send("""
                {"type":"error","message":"Invalid JSON payload. Expected action 'join' or 'message'"}
                """, promise: nil)
                return
            }

            Task {
                switch action.action {
                case "join":
                    let user = action.username ?? "User_\(clientId.uuidString.prefix(4))"
                    await room.setUsername(id: clientId, username: user)
                case "message":
                    let msg = action.text ?? ""
                    await room.broadcastChat(id: clientId, text: msg)
                default:
                    ws.send("""
                    {"type":"error","message":"Unknown action '\(action.action)'"}
                    """, promise: nil)
                }
            }
        }

        ws.onClose.whenComplete { _ in
            Task {
                await room.remove(id: clientId)
            }
        }
    }
}
