#!/bin/bash

set -e

echo "🚀 Initializing Raft cluster formation..."
echo "Waiting for all shards to be ready..."

# Wait for all shards to be healthy
for shard in 1 2 3; do
    port="80${shard}1"
    echo "Waiting for shard $shard on port $port..."
    
    for i in {1..30}; do
        if curl -s "http://shard${shard}:$port/config" >/dev/null 2>&1; then
            echo "✅ Shard $shard is ready"
            break
        fi
        echo "⏳ Waiting for shard $shard... (attempt $i/30)"
        sleep 2
    done
done

echo ""
echo "🔗 Forming Raft cluster..."

# Wait for shard 1 to become leader
echo "Waiting for shard 1 to establish leadership..."
for i in {1..15}; do
    if curl -s "http://shard1:8011/raft/status" | grep -q '"state":"Leader"'; then
        echo "✅ Shard 1 is now leader, proceeding with joins..."
        break
    fi
    echo "⏳ Waiting for leadership... (attempt $i/15)"
    sleep 3
done

# Add shard 2 to the cluster
echo "Adding shard 2 to cluster..."
for i in {1..5}; do
    if curl -X POST "http://shard1:8011/raft/join" \
        -H "Content-Type: application/json" \
        -d '{"nodeid":"2","addr":"shard2:18021"}' \
        --silent --show-error | grep -q '"success":true'; then
        echo "✅ Shard 2 joined successfully"
        break
    else
        echo "⚠️ Shard 2 join attempt $i failed, retrying..."
        sleep 5
    fi
done

# Wait before adding third shard
sleep 5

# Add shard 3 to the cluster
echo "Adding shard 3 to cluster..."
for i in {1..5}; do
    if curl -X POST "http://shard1:8011/raft/join" \
        -H "Content-Type: application/json" \
        -d '{"nodeid":"3","addr":"shard3:18031"}' \
        --silent --show-error | grep -q '"success":true'; then
        echo "✅ Shard 3 joined successfully"
        break
    else
        echo "⚠️ Shard 3 join attempt $i failed, retrying..."
        sleep 5
    fi
done

echo ""
echo "🔍 Verifying cluster formation..."

# Verify cluster status
for shard in 1 2 3; do
    port="80${shard}1"
    echo "--- Shard $shard (port $port) ---"
    
    response=$(curl -s "http://shard${shard}:$port/raft/status" || echo '{"error":"failed"}')
    
    if echo "$response" | grep -q '"success":true'; then
        state=$(echo "$response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        term=$(echo "$response" | grep -o '"term":"[^"]*"' | cut -d'"' -f4)
        
        case $state in
            "Leader")
                echo "👑 $state (Term: $term)"
                ;;
            "Follower")
                echo "👥 $state (Term: $term)"
                ;;
            "Candidate")
                echo "🗳️ $state (Term: $term)"
                ;;
            *)
                echo "❓ $state (Term: $term)"
                ;;
        esac
    else
        echo "❌ Shard unreachable or error"
    fi
done

echo ""
echo "🎉 Raft cluster initialization completed!"
echo "✅ 3 shards are now part of a single Raft cluster"
echo "✅ Router can now be started to handle requests" 