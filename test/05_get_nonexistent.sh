#!/bin/bash

echo "=== GET Operation (Non-existent Key) ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Attempting to retrieve non-existent key..."
echo "URL: $ROUTER_URL/get"
echo "Body: {\"key\": \"nonexistent_key\"}"
echo ""

response=$(curl -s -X GET "$ROUTER_URL/get" \
    -H "Content-Type: application/json" \
    -d '{"key": "nonexistent_key"}')
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if GET properly handles non-existent key
if echo "$response" | jq -e '.success == false' >/dev/null 2>&1; then
    echo "✅ Correctly returned error for non-existent key"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
else
    echo "⚠️  Unexpected response for non-existent key"
fi 