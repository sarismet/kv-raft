#!/bin/bash

echo "=== Router Status Check ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Checking router status..."
response=$(curl -s "$ROUTER_URL/status")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if router is healthy
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    shard_count=$(echo "$response" | jq -r '.data.shardCount')
    echo "✅ Router is healthy with $shard_count shards"
else
    echo "❌ Router is not healthy"
fi 