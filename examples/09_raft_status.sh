#!/bin/bash

echo "=== Raft Cluster Status Check ==="
echo ""

echo "Checking Raft status for all shards in the cluster..."
echo "Architecture: 3 shards forming 1 Raft cluster"
echo ""

for shard in 1 2 3; do
    port="80${shard}1"
    echo "--- Shard $shard (port $port) ---"
    
    response=$(curl -s "http://localhost:$port/raft/status")
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        state=$(echo "$response" | jq -r '.data.state')
        term=$(echo "$response" | jq -r '.data.term')
        num_peers=$(echo "$response" | jq -r '.data.num_peers')
        leader=$(echo "$response" | jq -r '.data.leader // "unknown"')
        
        case $state in
            "Leader")
                echo "👑 $state (Term: $term, Peers: $num_peers)"
                echo "   This shard is the cluster leader"
                ;;
            "Follower")
                echo "👥 $state (Term: $term, Leader: $leader)"
                echo "   This shard follows the cluster leader"
                ;;
            "Candidate")
                echo "🗳️  $state (Term: $term)"
                echo "   This shard is campaigning for leadership"
                ;;
            *)
                echo "❓ $state (Term: $term)"
                echo "   Unknown state"
                ;;
        esac
        
        # Show additional cluster info for leader
        if [ "$state" = "Leader" ]; then
            echo "   Cluster members: $((num_peers + 1)) total"
        fi
    else
        echo "❌ Shard unreachable or error"
        echo "Response: $response"
    fi
    echo ""
done

echo "=== Cluster Summary ==="
echo "Expected: 3 shards, 1 leader, 2 followers"
echo "If all shards show the same term number, the cluster is healthy" 