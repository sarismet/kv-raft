#!/bin/bash

echo "=== Raft Status Check ==="
echo ""

echo "Checking Raft status from all shards in the cluster..."
echo "Architecture: 3 shards forming 1 Raft cluster"
echo ""

for shard in 1 2 3; do
    port="80${shard}1"
    echo "--- Shard $shard (port $port) ---"
    
    response=$(curl -s "http://shard${shard}:$port/raft/status")
    echo "Raw response: $response"
    echo ""
    
    echo "Formatted response:"
    echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
    echo ""
    
    # Extract Raft information
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        state=$(echo "$response" | jq -r '.data.state')
        term=$(echo "$response" | jq -r '.data.term')
        num_peers=$(echo "$response" | jq -r '.data.num_peers')
        
        case $state in
            "Leader")
                echo "👑 Shard $shard is the LEADER (Term: $term, Peers: $num_peers)"
                ;;
            "Follower")
                echo "👥 Shard $shard is a FOLLOWER (Term: $term, Peers: $num_peers)"
                ;;
            "Candidate")
                echo "🗳️ Shard $shard is a CANDIDATE (Term: $term, Peers: $num_peers)"
                ;;
            *)
                echo "❓ Shard $shard has unknown state: $state (Term: $term, Peers: $num_peers)"
                ;;
        esac
        
        # Show cluster configuration
        echo "Cluster configuration:"
        echo "$response" | jq -r '.data.latest_configuration // "No configuration available"'
        
    else
        echo "❌ Shard $shard is not responding properly"
    fi
    
    echo ""
done

echo "=== Raft Summary ==="
echo "Expected: 1 Leader and 2 Followers, all in the same term"
echo "If all nodes show the same term, the cluster is synchronized" 