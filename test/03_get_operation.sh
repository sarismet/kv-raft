#!/bin/bash

echo "=== GET Operation ==="
echo ""

ROUTER_URL="http://router:3000"

echo "Retrieving user1 (should exist from previous PUT)..."
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

# Check if GET was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    value=$(echo "$response" | jq -r '.data.value')
    echo "✅ GET operation successful"
    echo "Retrieved value: $value"
    
    if [ "$value" = "john_doe" ]; then
        echo "✅ Value matches expected result"
    else
        echo "⚠️  Value doesn't match expected result (expected: john_doe, got: $value)"
    fi
else
    echo "❌ GET operation failed"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
fi 