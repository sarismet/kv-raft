#!/bin/bash

echo "=== DELETE Operation ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Deleting user1 (should exist from previous PUT)..."
echo "URL: $ROUTER_URL/delete"
echo "Body: {\"key\": \"user1\"}"
echo ""

response=$(curl -s -X DELETE "$ROUTER_URL/delete" \
    -H "Content-Type: application/json" \
    -d '{"key": "user1"}')
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if DELETE was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ DELETE operation successful"
    echo "Message: $(echo "$response" | jq -r '.message // "Key deleted"')"
else
    echo "❌ DELETE operation failed"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
    
    # Check if it's a connection error
    if [[ "$error" == *"Cannot connect"* ]]; then
        echo ""
        echo "🔍 This appears to be a connection error to a shard."
        echo "   Check if all shards are running and accessible."
    fi
fi 