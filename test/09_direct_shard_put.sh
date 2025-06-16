#!/bin/bash

echo "=== Direct Shard PUT Operation ==="
echo ""

echo "Sending PUT request directly to shard 1 (bypassing router)..."
echo "URL: http://shard1:8011/put?key=direct_test&val=shard_direct_value"
echo ""

response=$(curl -s -X POST "http://shard1:8011/put?key=direct_test&val=shard_direct_value")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if direct PUT was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ Direct shard PUT operation successful"
    echo "Message: $(echo "$response" | jq -r '.message // "Key stored"')"
else
    echo "❌ Direct shard PUT operation failed"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
fi

echo ""
echo "Note: This operation bypasses the router and writes directly to shard 1"
echo "The data should be replicated to other shards via Raft consensus" 