#!/bin/bash

echo "=== Direct Shard GET ==="
echo ""

SHARD_URL="http://localhost:8011"  # Shard 1, Node 1

echo "Sending GET request directly to shard..."
echo "URL: $SHARD_URL/get?key=direct_key"
echo ""

response=$(curl -s "$SHARD_URL/get?key=direct_key")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if GET was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    key=$(echo "$response" | jq -r '.key')
    value=$(echo "$response" | jq -r '.value')
    echo "✅ Direct GET operation successful"
    echo "Key: $key"
    echo "Value: $value"
else
    echo "❌ Direct GET operation failed"
    error=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "Error: $error"
fi 