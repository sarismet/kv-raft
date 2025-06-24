#!/bin/bash

LOGDIR=logs

# Create logs directory if it doesn't exist
mkdir -p "$LOGDIR"

run_single_shard () {
    SHARD_ID=$1
    PORT=$2
    RAFT_PORT=$3

    echo "Starting shard $SHARD_ID on port $PORT (raft: $RAFT_PORT)"
    
    # Start single shard node
    go run -C shard . --shard_id "$SHARD_ID" --node_id "$SHARD_ID" --port "$PORT" --raft_addr "localhost:$RAFT_PORT" \
        &> "$LOGDIR/shard_${SHARD_ID}.log" &
    echo "Shard $SHARD_ID started (pid $!)"
}

form_raft_cluster () {
    echo "Waiting for all shards to initialize..."
    sleep 8

    echo "Forming Raft cluster..."
    
    # Wait for shard 1 to become leader
    echo "Waiting for shard 1 to establish leadership..."
    for i in {1..10}; do
        if curl -s "localhost:8011/raft/status" | grep -q '"state":"Leader"'; then
            echo "Shard 1 is now leader, proceeding with joins..."
            break
        fi
        echo "Waiting for leadership... (attempt $i/10)"
        sleep 2
    done
    
    # Add shard 2 to the cluster
    echo "Adding shard 2 to cluster..."
    for i in {1..3}; do
        if curl -X POST "localhost:8011/raft/join" \
            -H "Content-Type: application/json" \
            -d '{"nodeid":"2","addr":"localhost:18021"}' \
            --silent --show-error | grep -q '"success":true'; then
            echo "✓ Shard 2 joined successfully"
            break
        else
            echo "⚠ Shard 2 join attempt $i failed, retrying..."
            sleep 3
        fi
    done
    
    # Wait a bit before adding the third shard
    sleep 3
    
    # Add shard 3 to the cluster
    echo "Adding shard 3 to cluster..."
    for i in {1..3}; do
        if curl -X POST "localhost:8011/raft/join" \
            -H "Content-Type: application/json" \
            -d '{"nodeid":"3","addr":"localhost:18031"}' \
            --silent --show-error | grep -q '"success":true'; then
            echo "✓ Shard 3 joined successfully"
            break
        else
            echo "⚠ Shard 3 join attempt $i failed, retrying..."
            sleep 3
        fi
    done

    sleep 5
    echo "Raft cluster formation completed!"
}

verify_cluster () {
    echo "Verifying cluster status..."
    echo ""
    
    for shard in 1 2 3; do
        port="80${shard}1"
        echo "--- Shard $shard (port $port) ---"
        
        # Check Raft status
        echo "Raft status:"
        curl -s "localhost:$port/raft/status" | jq '.data.state // .state' 2>/dev/null || echo "Failed to get status"
        
        # Check configuration
        echo "Configuration:"
        curl -s "localhost:$port/config" | jq '.data.shards // {}' 2>/dev/null || echo "Failed to get config"
        echo ""
    done
}

run_all () {
    echo "Starting 3-shard Raft cluster..."
    echo "Each shard is a single Go application"
    echo ""

    # Start the 3 shards
    run_single_shard 1 8011 18011
    run_single_shard 2 8021 18021  
    run_single_shard 3 8031 18031

    # Form the Raft cluster
    form_raft_cluster
    
    # Wait for stabilization
    echo "Waiting for cluster to stabilize..."
    sleep 10
    
    # Verify the cluster
    verify_cluster

    echo ""
    echo "🎉 3-shard Raft cluster is ready!"
    echo ""
    echo "System is running with the following endpoints:"
    echo "  - Shard 1: http://localhost:8011 (raft: localhost:18011)"
    echo "  - Shard 2: http://localhost:8021 (raft: localhost:18021)" 
    echo "  - Shard 3: http://localhost:8031 (raft: localhost:18031)"
    echo "  - Router will be: http://localhost:3000"
    echo ""
    echo "You can now:"
    echo "  1. Start Python router: ./scripts/run_router.sh"
    echo "  2. Test the system: ./examples/run_all_examples.sh"
    echo ""
    
    echo "Shards are running. Start a router separately to begin routing requests."
    
    wait
}

# Function to check if required tools are available
check_dependencies() {
    if ! command -v go &> /dev/null; then
        echo "Error: Go is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed"
        exit 1
    fi
    
    echo "✓ Dependencies check passed"
}

echo "🚀 Starting 3-shard distributed KV system"
echo "Architecture: 3 Go applications forming 1 Raft cluster"
echo "Each shard manages its own data and participates in consensus"
echo ""

# Check dependencies first
check_dependencies

(trap "echo 'Killing all processes...'; kill 0" SIGINT; run_all)
