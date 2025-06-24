#!/bin/bash

echo "=== PUT Operation (JSON Body) ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Sending PUT request with JSON body..."
echo "URL: $ROUTER_URL/put"
echo "Body: {\"key\": \"user1\", \"val\": \"john_doe\"}"
echo ""

response=$(curl -s -X POST "$ROUTER_URL/put" \
    -H "Content-Type: application/json" \
    -d '{"key": "user1", "val": "john_doe"}')

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
    echo ""
    echo "Note: This might be a bug in the Python router's JSON body handling for PUT requests."
fi 