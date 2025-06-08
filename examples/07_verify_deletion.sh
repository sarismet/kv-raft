#!/bin/bash

echo "=== Verify Deletion ==="
echo ""

ROUTER_URL="http://localhost:3000"

echo "Verifying deletion by trying to GET the deleted key 'user2'..."
echo "URL: $ROUTER_URL/get?key=user2"
echo ""

response=$(curl -s "$ROUTER_URL/get?key=user2")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if key was actually deleted
if echo "$response" | jq -e '.success == false and .error == "Key not found"' >/dev/null 2>&1; then
    echo "✅ Deletion verified: Key not found (as expected)"
elif echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "❌ Deletion failed: Key still exists"
    value=$(echo "$response" | jq -r '.value')
    echo "Current value: $value"
else
    echo "❌ Unexpected error during verification"
    error=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "Error: $error"
fi 