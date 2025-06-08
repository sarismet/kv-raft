#!/bin/bash

echo "=== PUT Operation (Query Parameters) ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Sending PUT request with query parameters..."
echo "URL: $ROUTER_URL/put?key=user1&val=john_doe"
echo ""

response=$(curl -s "$ROUTER_URL/put?key=user1&val=john_doe")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if PUT was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ PUT operation successful"
else
    echo "❌ PUT operation failed"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
fi 