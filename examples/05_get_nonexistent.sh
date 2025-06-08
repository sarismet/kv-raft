#!/bin/bash

echo "=== GET Operation (Non-existent Key) ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Sending GET request for non-existent key 'nonexistent'..."
echo "URL: $ROUTER_URL/get?key=nonexistent"
echo ""

response=$(curl -s "$ROUTER_URL/get?key=nonexistent")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check response
if echo "$response" | jq -e '.success == false and .error == "Key not found"' >/dev/null 2>&1; then
    echo "✅ Expected behavior: Key not found"
elif echo "$response" | jq -e '.success == false' >/dev/null 2>&1; then
    error=$(echo "$response" | jq -r '.error')
    echo "❌ Unexpected error: $error"
else
    echo "❌ Unexpected response format"
fi 