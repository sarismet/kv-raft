#!/bin/bash

echo "=== Shard Configuration Check ==="
echo ""

echo "Checking configuration from all shards in the cluster..."
echo "Architecture: 3 shards forming 1 Raft cluster"
echo ""

for shard in 1 2 3; do
    port="80${shard}1"
    echo "--- Shard $shard (port $port) ---"
    
    response=$(curl -s "http://shard${shard}:$port/config")
    echo "Raw response: $response"
    echo ""
    
    echo "Formatted response:"
    echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
    echo ""
    
    # Extract shard information
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        shard_count=$(echo "$response" | jq -r '.data.shardCount')
        echo "✅ Shard $shard is healthy with $shard_count total shards in cluster"
        
        echo "Known shards in cluster:"
        echo "$response" | jq -r '.data.shards | to_entries[] | "  Shard \(.key): \(.value)"'
        
        # Check if this shard knows about all expected shards
        if [ "$shard_count" = "3" ]; then
            echo "✅ Cluster membership is complete (3/3 shards)"
        else
            echo "⚠️  Cluster membership incomplete ($shard_count/3 shards)"
        fi
    else
        echo "❌ Shard $shard is not responding properly"
    fi
    
    echo ""
done

echo "=== Configuration Summary ==="
echo "Expected: All shards should know about 3 total shards"
echo "If all shards show the same configuration, the cluster is synchronized" 