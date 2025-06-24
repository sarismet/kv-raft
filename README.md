# KV-Raft: Distributed Key-Value Store with Raft Consensus

A distributed key-value storage system built with Go and Python, featuring Raft consensus algorithm for strong consistency and fault tolerance. The system uses a unified architecture where 3 shards form a single Raft cluster, eliminating the need for separate configuration servers.

## 🏗️ System Architecture

### Shard Architecture (ASCII Diagram)
```
                    Client Requests
                          |
                          v
    ┌─────────────────────────────────────────────────────┐
    │                   ROUTER                            │
    │                                                     │
    │                  (Python)                           │
    │         - Routes requests to leader                 │
    │         - Detects current Raft leader               │
    │         - Load balances read operations             │
    └────────────────────────┬────────────────────────────┘
                             |
                ┌────────────┼────────────┐
                |            |            |
                v            v            v
            ┌─────────┐  ┌─────────┐  ┌─────────┐
            │ SHARD 1 │  │ SHARD 2 │  │ SHARD 3 │
            │ (Go)    │  │ (Go)    │  │ (Go)    │
            │ Node 1  │  │ Node 2  │  │ Node 3  │
            │         │  │         │  │         │
            │ Port:   │  │ Port:   │  │ Port:   │
            │ 8011    │  │ 8021    │  │ 8031    │
            │         │  │         │  │         │
            │ Raft:   │  │ Raft:   │  │ Raft:   │
            │ 18011   │  │ 18021   │  │ 18031   │
            └─────────┘  └─────────┘  └─────────┘
                ^            ^            ^
                |            |            |
                └────────────┼────────────┘
                            |
                    Raft Consensus
                (Leader Election & Log Replication)
```

### Raft Cluster Formation
```
    Initial State: All nodes start independently
    
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Shard 1 │    │ Shard 2 │    │ Shard 3 │
    (Candidate)    (Candidate)    (Candidate)
    └─────────┘    └─────────┘    └─────────┘
    
    After Bootstrap: One leader, two followers
    
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Shard 1 │◄──►│ Shard 2 │◄──►│ Shard 3 │
    │ LEADER  │    │FOLLOWER │    │FOLLOWER │
    │         │    │         │    │         │
    └─────────┘    └─────────┘    └─────────┘
```

### Request Flow
```
    Write Operations (PUT/DELETE):
    Client -> Router -> Leader Shard -> Raft Consensus -> All Shards
    
    Read Operations (GET):
    Client -> Router -> Any Shard (Load Balanced)
    
    Leader Detection:
    Router -> Query All Shards -> Find Current Leader -> Route Writes
```

## 🐳 Docker Services

The system runs entirely in Docker containers with the following services:

| Service | Description | Ports | Dependencies |
|---------|-------------|-------|--------------|
| **shard1** | Go-based shard server (Node 1) | 8011, 18011 | None |
| **shard2** | Go-based shard server (Node 2) | 8021, 18021 | None |
| **shard3** | Go-based shard server (Node 3) | 8031, 18031 | None |
| **cluster-init** | Initializes Raft cluster formation | None | All shards healthy |
| **router** | Python API gateway | 3000 | Cluster initialized |
| **test-runner** | Automated test execution every 30 seconds | None | Router healthy |

### Service Details

#### Shards (shard1, shard2, shard3)
- **Technology**: Go with Raft consensus
- **Purpose**: Store key-value data with strong consistency
- **Raft Roles**: One leader, two followers (elected automatically)
- **Data Storage**: In-memory with Raft log persistence
- **Health Check**: HTTP GET `/config` endpoint

#### Router
- **Technology**: Python aiohttp (async)
- **Purpose**: API gateway and request routing
- **Features**:
  - Detects current Raft leader for write operations
  - Load balances read operations across all shards
  - Provides unified API interface
- **Health Check**: HTTP GET `/status` endpoint

#### Cluster-Init
- **Purpose**: Ensures proper Raft cluster formation
- **Function**: Waits for all shards to be healthy, then triggers cluster bootstrap
- **Lifecycle**: Runs once and exits successfully

#### Test-Runner
- **Purpose**: Continuous integration testing
- **Function**: Runs comprehensive API tests every 30 seconds
- **Environment**: Configurable test interval via `TEST_INTERVAL`

## 🚀 Running with Docker Compose

### Prerequisites
- Docker and Docker Compose installed
- Ports 3000, 8011, 8021, 8031, 18011, 18021, 18031 available

### Quick Start
```bash
# Start all services
docker-compose up

# Start in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

### Service Health Monitoring
```bash
# Check service status
docker-compose ps

# View specific service logs
docker-compose logs shard1
docker-compose logs router
docker-compose logs test-runner
```

## 🔧 How It Works

### Shard Functionality
Each shard is a complete Go server that:
1. **Stores Data**: Maintains key-value pairs in memory
2. **Raft Consensus**: Participates in leader election and log replication
3. **HTTP API**: Provides REST endpoints for data operations
4. **Peer Communication**: Communicates with other shards via Raft protocol

### Router Functionality
The router acts as an intelligent proxy that:
1. **Leader Detection**: Queries all shards to find the current Raft leader
2. **Write Routing**: Routes PUT/DELETE operations to the leader shard
3. **Read Load Balancing**: Distributes GET operations across all shards
4. **Error Handling**: Retries and failover logic for network issues

### Raft Consensus Process
1. **Leader Election**: Shards elect a leader using Raft algorithm
2. **Log Replication**: Leader replicates all changes to followers
3. **Consistency**: All shards maintain identical data state
4. **Fault Tolerance**: System continues operating if 1 shard fails

## 📡 API Endpoints

### Router API (Port 3000)
```bash
# System status
curl http://localhost:3000/status

# Store a key-value pair (JSON body required)
curl -X POST "http://localhost:3000/put" \
  -H "Content-Type: application/json" \
  -d '{"key": "mykey", "val": "myvalue"}'

# Retrieve a value (query parameters only)
curl "http://localhost:3000/get?key=mykey"

# Delete a key (JSON body required)
curl -X DELETE "http://localhost:3000/delete" \
  -H "Content-Type: application/json" \
  -d '{"key": "mykey"}'
```

### Direct Shard API (Ports 8011, 8021, 8031)
```bash
# Shard configuration
curl http://localhost:8011/config

# Raft cluster status
curl http://localhost:8011/raft/status

# Direct data operations (use leader shard)
curl -X POST "http://localhost:8011/put" \
  -H "Content-Type: application/json" \
  -d '{"key": "test", "val": "value"}'
curl "http://localhost:8011/get?key=test"
```

## 🧪 Testing

### Automated Testing
The system includes comprehensive automated tests that run continuously:

```bash
# View test results
docker-compose logs test-runner
```

### Test Coverage
- Router status and connectivity
- PUT/GET/DELETE operations
- Error handling and edge cases
- Direct shard operations
- Raft cluster status verification

### Manual Testing
```bash
# Test basic operations
curl -X POST "http://localhost:3000/put" \
  -H "Content-Type: application/json" \
  -d '{"key": "test1", "val": "hello"}'
curl "http://localhost:3000/get?key=test1"

# Delete using JSON body (required)
curl -X DELETE "http://localhost:3000/delete" \
  -H "Content-Type: application/json" \
  -d '{"key": "test1"}'

# Verify cluster status
curl http://localhost:3000/status
# Should return: {"shardCount": 3}
```

## 🔍 Monitoring and Debugging

### Service Health
```bash
# Check all services
docker-compose ps

# View real-time logs
docker-compose logs -f router
docker-compose logs -f shard1
```

### Raft Cluster Status
```bash
# Check which shard is the leader
curl http://localhost:8011/raft/status
curl http://localhost:8021/raft/status  
curl http://localhost:8031/raft/status
```

## 🏗️ Architecture Benefits

1. **Strong Consistency**: Raft consensus ensures all shards have identical data
2. **Fault Tolerance**: System survives single shard failures
3. **Automatic Leader Election**: No manual intervention needed for failover
4. **Unified Cluster**: Single Raft cluster eliminates configuration complexity
5. **Docker Native**: Fully containerized with service discovery
6. **Continuous Testing**: Automated validation of system health

## 🔧 Configuration

### Environment Variables
- `TEST_INTERVAL`: Test execution interval in seconds (default: 30)
- `PORT`: Router port (default: 3000)
- `SHARD_PORTS`: Comma-separated shard ports

### Network Configuration
- **Network**: `kv-raft-network` (Docker bridge)
- **Service Discovery**: Docker DNS resolution
- **Internal Communication**: Docker service names (shard1, shard2, shard3)

## 📁 Project Structure
```
kv-raft/
├── shard/          # Go shard server implementation
├── router/         # Python router
├── cluster/        # Cluster initialization scripts
├── test/           # Automated test scripts
├── docker-compose.yml
└── README.md
```

This distributed system provides a robust, fault-tolerant key-value store with strong consistency guarantees through Raft consensus, all running seamlessly in Docker containers.

## 🙏 Acknowledgments

This project was inspired by the distributed key-value store implementation at [@aemirbosnak/distributed-key-value-store](https://github.com/aemirbosnak/distributed-key-value-store). The original repository provided valuable insights into distributed systems architecture and Raft consensus implementation patterns. 