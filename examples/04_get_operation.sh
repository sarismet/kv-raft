#!/bin/bash

echo "=== GET Operation ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Sending GET request for key 'user1'..."
echo "URL: $ROUTER_URL/get?key=user1"
echo ""

response=$(curl -s "$ROUTER_URL/get?key=user1")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if GET was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    key=$(echo "$response" | jq -r '.key')
    value=$(echo "$response" | jq -r '.value')
    echo "✅ GET operation successful"
    echo "Key: $key"
    echo "Value: $value"
else
    echo "❌ GET operation failed"
    error=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "Error: $error"
    
    # Check if it's a connection error
    if [[ "$error" == *"Cannot connect"* ]]; then
        echo ""
        echo "🔍 This appears to be a connection error to a shard."
        echo "   Check if all shards are running and accessible."
    fi
fi 