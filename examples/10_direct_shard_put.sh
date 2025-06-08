#!/bin/bash

echo "=== Direct Shard PUT (JSON) ==="
echo ""

SHARD_URL="http://localhost:8011"  # Shard 1, Node 1

echo "Sending PUT request directly to shard..."
echo "URL: $SHARD_URL/put"
echo "Content-Type: application/json"
echo "Body: {\"key\":\"direct_key\",\"val\":\"direct_value\"}"
echo ""

response=$(curl -s -H "Content-Type: application/json" \
     -d '{"key":"direct_key","val":"direct_value"}' \
     "$SHARD_URL/put")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if PUT was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    key=$(echo "$response" | jq -r '.data.key')
    value=$(echo "$response" | jq -r '.data.value')
    echo "✅ Direct PUT operation successful"
    echo "Key: $key"
    echo "Value: $value"
else
    echo "❌ Direct PUT operation failed"
    error=$(echo "$response" | jq -r '.error // "Unknown error"')
    echo "Error: $error"
fi 