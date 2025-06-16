#!/bin/bash

echo "=== Verify Deletion ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Attempting to retrieve deleted key (user1)..."
echo "URL: $ROUTER_URL/get"
echo "Body: {\"key\": \"user1\"}"
echo ""

response=$(curl -s -X GET "$ROUTER_URL/get" \
    -H "Content-Type: application/json" \
    -d '{"key": "user1"}')
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if key was properly deleted
if echo "$response" | jq -e '.success == false' >/dev/null 2>&1; then
    echo "✅ Deletion verified - key no longer exists"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
else
    echo "⚠️  Key still exists after deletion"
    echo "Value: $(echo "$response" | jq -r '.data.value // "No value"')"
fi 