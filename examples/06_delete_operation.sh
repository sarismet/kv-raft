#!/bin/bash

echo "=== DELETE Operation ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Sending DELETE request for key 'user2'..."
echo "URL: $ROUTER_URL/delete?key=user2"
echo ""

response=$(curl -s -X DELETE "$ROUTER_URL/delete?key=user2")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if DELETE was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ DELETE operation successful"
else
    echo "❌ DELETE operation failed"
    error=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "Error: $error"
    
    # Check if it's a connection error
    if [[ "$error" == *"Cannot connect"* ]]; then
        echo ""
        echo "🔍 This appears to be a connection error to a shard."
        echo "   Check if all shards are running and accessible."
    fi
fi 