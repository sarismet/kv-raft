#!/bin/bash

echo "=== PUT Operation (JSON Body) ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Sending PUT request with JSON body..."
echo "Content-Type: application/json"
echo "Body: {\"key\":\"user2\",\"val\":\"jane_smith\"}"
echo ""

response=$(curl -s -H "Content-Type: application/json" \
     -d '{"key":"user2","val":"jane_smith"}' \
     "$ROUTER_URL/put")
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