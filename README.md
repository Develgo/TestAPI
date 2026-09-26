# TestAPI: Multi-Protocol Test Server (REST, WebSocket, gRPC)

A multi-protocol test server built with Swift, **Vapor 4**, and **gRPC Swift 2**. Designed to validate and benchmark various client implementations (HTTP/REST, WebSocket, and gRPC) against an interactive, real-time **Product Catalog & Inventory** domain.

---

## Architecture Overview

All protocols share an in-memory, thread-safe `ProductRepository` (`actor`). Any updates performed through REST or gRPC immediately reflect across all interfaces and trigger real-time broadcast events over WebSocket and gRPC streaming channels.

- **HTTP REST & WebSockets**: Port `8080` (Vapor HTTP Server)
- **gRPC Services**: Port `50051` (HTTP/2 gRPC Server via `grpc-swift-2` and `grpc-swift-nio-transport`)

---

## Getting Started

### Build & Run

```bash
# Build the project
swift build

# Run automated tests
swift test

# Start the servers (REST/WebSocket on 8080, gRPC on 50051)
swift run TestAPI
```

---

## 1. REST Endpoints (Port 8080)

### Root Discovery
| Method | Path | Description |
|---|---|---|
| `GET` | `/` | API service directory and status |

```bash
curl -s http://localhost:8080/ | jq .
```

### Products CRUD (`/api/v1/products`)
| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/products` | List products with filtering, sorting, pagination |
| `GET` | `/api/v1/products/:id` | Get single product by UUID |
| `POST` | `/api/v1/products` | Create a new product (returns `201 Created` + `Location` header) |
| `PUT` | `/api/v1/products/:id` | Full replacement / update |
| `PATCH` | `/api/v1/products/:id` | Partial update |
| `DELETE` | `/api/v1/products/:id` | Delete product (returns `204 No Content`) |

#### Examples:

```bash
# 1. List with filtering, pagination, and sorting
curl -s "http://localhost:8080/api/v1/products?category=electronics&minPrice=100&page=1&per=5&sort=price&order=desc" | jq .

# 2. Get single product by ID
curl -s http://localhost:8080/api/v1/products/11111111-1111-1111-1111-111111111111 | jq .

# 3. Create a product
curl -i -X POST http://localhost:8080/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mechanical Numpad",
    "description": "External wireless numpad with hot-swap switches.",
    "price": 39.99,
    "category": "electronics",
    "sku": "TECH-NUM-001",
    "stockQuantity": 50,
    "tags": ["accessories", "keyboard"]
  }'

# 4. Partial update (PATCH)
curl -s -X PATCH http://localhost:8080/api/v1/products/11111111-1111-1111-1111-111111111111 \
  -H "Content-Type: application/json" \
  -d '{"price": 1799.99, "stockQuantity": 20}' | jq .

# 5. Delete product
curl -i -X DELETE http://localhost:8080/api/v1/products/11111111-1111-1111-1111-111111111111
```

### Client Diagnostics (`/api/v1/test`)
| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/test/status/:code` | Returns requested HTTP status code (200, 201, 204, 400, 401, 404, 418, 500, etc.) |
| `GET` | `/api/v1/test/delay?seconds=N` | Simulates server latency (up to 10s) |
| `GET/POST` | `/api/v1/test/headers` | Echoes incoming client headers & injects `X-Server-Time`, `ETag` |
| `ANY` | `/api/v1/test/inspect` | Inspects full request details including headers, body (raw & parsed JSON), query, and IP |
| `POST` | `/api/v1/test/upload` | Multipart form-data file upload test; returns size & SHA256 |
| `GET` | `/api/v1/test/download` | Downloads sample CSV file with `Content-Disposition` |

#### Examples:

```bash
# Test HTTP 418 I'm a teapot
curl -i http://localhost:8080/api/v1/test/status/418

# Test 2-second server latency
curl -s "http://localhost:8080/api/v1/test/delay?seconds=2" | jq .

# Inspect headers & response headers
curl -i http://localhost:8080/api/v1/test/headers -H "X-Client-Version: 2.0.0"

# Inspect full request details (headers, body, query parameters)
curl -i -X POST "http://localhost:8080/api/v1/test/inspect?debug=true" \
  -H "Content-Type: application/json" \
  -H "X-Client-Platform: CLI" \
  -d '{"message": "Hello TestAPI", "active": true, "count": 42}'

# Download test file
curl -OJ http://localhost:8080/api/v1/test/download
```

### Authentication Simulation (`/api/v1/auth`)
| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/auth/login` | Returns mock Bearer token (`test-bearer-token-abc123xyz`) |
| `GET` | `/api/v1/auth/me` | Protected route requiring `Authorization: Bearer <token>` |

#### Examples:

```bash
# Login
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"tester","password":"password"}' | jq .

# Access protected endpoint with Bearer token
curl -s http://localhost:8080/api/v1/auth/me \
  -H "Authorization: Bearer test-bearer-token-abc123xyz" | jq .

# Attempt access without token (returns 401)
curl -i http://localhost:8080/api/v1/auth/me
```

---

## 2. WebSocket Endpoints (Port 8080)

| Endpoint | Description |
|---|---|
| `ws://localhost:8080/ws/echo` | Echoes client text and binary frames with metadata |
| `ws://localhost:8080/ws/ticker` | Pushes continuous live product price ticks and catalog events |
| `ws://localhost:8080/ws/chat` | Multi-client broadcast room (supports `join` and `message` actions) |

### Testing WebSockets

#### Option A: Using modern browser console
```javascript
// Echo test
const ws = new WebSocket('ws://localhost:8080/ws/echo');
ws.onmessage = (e) => console.log('Echo response:', e.data);
ws.onopen = () => ws.send('Hello from browser client!');

// Live ticker test
const ticker = new WebSocket('ws://localhost:8080/ws/ticker');
ticker.onmessage = (e) => console.log('Ticker tick:', e.data);

// Multi-client chat test
const chat = new WebSocket('ws://localhost:8080/ws/chat');
chat.onopen = () => {
  chat.send(JSON.stringify({ action: "join", username: "Alice" }));
  chat.send(JSON.stringify({ action: "message", text: "Hello room!" }));
};
chat.onmessage = (e) => console.log('Chat message:', e.data);
```

#### Option B: Using Node.js or `wscat`
```bash
# Using wscat (npm i -g wscat)
wscat -c ws://localhost:8080/ws/echo
```

---

## 3. gRPC Endpoints (Port 50051)

Service definition is located in [Protos/products.proto](file:///Users/nitesh.maharaj/Development/projects/vapor-projects/TestAPI/Protos/products.proto).

| Method | Type | Description |
|---|---|---|
| `GetProduct` | **Unary** | Retrieve single product by ID |
| `ListProducts` | **Unary** | List products with pagination & category filter |
| `CreateProduct` | **Unary** | Create product entity |
| `StreamProductEvents` | **Server Streaming** | Stream continuous product catalog updates |
| `BatchCreateProducts` | **Client Streaming** | Stream multiple products to create in batch |
| `LiveInventorySync` | **Bidirectional Streaming** | Stream inventory adjustments and receive real-time stock balances |

### Testing with `grpcurl`

```bash
# 1. Unary: List products
grpcurl -plaintext -proto Protos/products.proto localhost:50051 products.ProductsService/ListProducts

# 2. Unary: Get product by ID
grpcurl -plaintext -proto Protos/products.proto \
  -d '{"id":"11111111-1111-1111-1111-111111111111"}' \
  localhost:50051 products.ProductsService/GetProduct

# 3. Unary: Create product
grpcurl -plaintext -proto Protos/products.proto \
  -d '{
    "name": "USB-C Fast Charger",
    "description": "65W GaN dual-port charger",
    "price": 29.99,
    "category": "ELECTRONICS",
    "sku": "TECH-CHG-001",
    "stockQuantity": 100
  }' \
  localhost:50051 products.ProductsService/CreateProduct

# 4. Client Streaming: Batch create products
echo '{"name":"Item 1","category":"BOOKS","price":15,"sku":"BK-01"}{"name":"Item 2","category":"FOOD","price":8,"sku":"FD-01"}' | \
  grpcurl -plaintext -proto Protos/products.proto -d @ localhost:50051 products.ProductsService/BatchCreateProducts

# 5. Bidirectional Streaming: Live inventory adjustment
echo '{"productId":"11111111-1111-1111-1111-111111111111","quantityDelta":-5}' | \
  grpcurl -plaintext -proto Protos/products.proto -d @ localhost:50051 products.ProductsService/LiveInventorySync

# 6. Server Streaming: Listen to real-time events
grpcurl -plaintext -proto Protos/products.proto localhost:50051 products.ProductsService/StreamProductEvents
```
