# Unified KV-Raft System (Cassandra-like Architecture)

This is a distributed key-value store that eliminates the need for separate config servers by implementing a Cassandra-like architecture where each shard manages its own configuration and broadcasts changes to peer shards.

## Architecture Overview

### Before (Original)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Config      │    │ Config      │    │ Config      │
│ Server 1    │    │ Server 2    │    │ Server 3    │
└─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
┌─────────┐        ┌─────────┐        ┌─────────┐
│ Shard 1 │        │ Shard 2 │        │ Shard 3 │
│ (3 nodes)│       │ (3 nodes)│       │ (3 nodes)│
└─────────┘        └─────────┘        └─────────┘
```

### After (Unified)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Unified     │◄──►│ Unified     │◄──►│ Unified     │
│ Shard 1     │    │ Shard 2     │    │ Shard 3     │
│ (Data+Config)│   │ (Data+Config)│   │ (Data+Config)│
│ (3 nodes)   │    │ (3 nodes)   │    │ (3 nodes)   │
└─────────────┘    └─────────────┘    └─────────────┘
```

## Key Features

1. **No Config Servers**: Each shard manages its own configuration
2. **Peer-to-Peer Discovery**: Shards broadcast their leader information to each other
3. **Automatic Failover**: When a shard leader changes, it automatically notifies all other shards
4. **Cassandra-like**: Equal shards with no central coordination point

## Running the System

### Option 1: Use the Unified Script (Recommended)
```bash
./scripts/run_unified.sh
```

This will start:
- 3 unified shards (each with 3 nodes)
- 1 router
- Automatic peer discovery between shards

### Option 2: Manual Startup

#### Start Shard 1
```bash
# Node 1 (Leader)
go run ./shard --shard_id 1 --node_id 1 --port 8011 --raft_addr localhost:18011 --peer_shards "localhost:8021,localhost:8031"

# Node 2
go run ./shard --shard_id 1 --node_id 2 --port 8012 --raft_addr localhost:18012 --peer_shards "localhost:8021,localhost:8031"

# Node 3  
go run ./shard --shard_id 1 --node_id 3 --port 8013 --raft_addr localhost:18013 --peer_shards "localhost:8021,localhost:8031"

# Join nodes to cluster
curl -d "nodeid=2&addr=localhost:18012" "localhost:8011/raft/join"
curl -d "nodeid=3&addr=localhost:18013" "localhost:8011/raft/join"
```

#### Start Shard 2
```bash
# Similar process for shard 2 with ports 8021, 8022, 8023 and raft ports 18021, 18022, 18023
```

#### Start Shard 3
```bash
# Similar process for shard 3 with ports 8031, 8032, 8033 and raft ports 18031, 18032, 18033
```

#### Start Router
```bash
go run ./router --shard_ports "8011,8021,8031"
```

## API Endpoints

### Data Operations (via Router on port 3000)
```bash
# Put a key-value pair
curl "localhost:3000/put?key=mykey&val=myvalue"

# Get a value
curl "localhost:3000/get?key=mykey"

# Delete a key
curl -X DELETE "localhost:3000/delete?key=mykey"

# Get router status
curl "localhost:3000/status"
```

### Direct Shard Operations
```bash
# Get configuration from any shard
curl "localhost:8011/config"

# Add a new shard (broadcast to all peers)
curl "localhost:8011/addshard?shardID=4&shardAddress=localhost:8041"

# Raft cluster management
curl "localhost:8011/raft/status"
```

## Configuration Broadcasting

When a shard leader changes or a new shard is added:

1. **Leader Change**: The new leader automatically broadcasts its information to all known peer shards
2. **New Shard**: When a shard is added via `/addshard`, the information is broadcast to all known peers
3. **Peer Discovery**: Each shard maintains a list of peer shards and keeps them updated

## Advantages of Unified Architecture

1. **Simplified Deployment**: No need to manage separate config servers
2. **Better Fault Tolerance**: No single point of failure for configuration
3. **Reduced Complexity**: Fewer moving parts to manage
4. **Cassandra-like Scalability**: Easy to add new shards without central coordination
5. **Self-Healing**: Automatic peer discovery and leader change notifications

## Port Layout

- **Shard 1**: HTTP 8011-8013, Raft 18011-18013
- **Shard 2**: HTTP 8021-8023, Raft 18021-18023  
- **Shard 3**: HTTP 8031-8033, Raft 18031-18033
- **Router**: HTTP 3000

## Logs

All logs are stored in the `logs/` directory:
- `unified_1_1.log`, `unified_1_2.log`, `unified_1_3.log` - Shard 1 nodes
- `unified_2_1.log`, `unified_2_2.log`, `unified_2_3.log` - Shard 2 nodes  
- `unified_3_1.log`, `unified_3_2.log`, `unified_3_3.log` - Shard 3 nodes
- `router.log` - Router logs

## Comparison with Original Architecture

| Feature | Original (Config Servers) | Unified (Cassandra-like) |
|---------|---------------------------|--------------------------|
| Config Management | Centralized (3 config servers) | Distributed (each shard) |
| Single Point of Failure | Yes (config servers) | No |
| Deployment Complexity | High (2 types of servers) | Low (1 type of server) |
| Scalability | Limited by config servers | Unlimited |
| Peer Discovery | Via config servers | Direct peer-to-peer |
| Fault Tolerance | Config server dependent | Self-healing | 