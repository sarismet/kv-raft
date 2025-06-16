#!/bin/bash

echo "=== Direct Shard GET Operation ==="
echo ""

echo "Retrieving key directly from shard 1 (bypassing router)..."
echo "URL: http://shard1:8011/get?key=direct_test"
echo ""

response=$(curl -s "http://shard1:8011/get?key=direct_test")
echo "Raw response: $response"
echo ""

echo "Formatted response:"
echo "$response" | jq '.' 2>/dev/null || echo "Failed to parse JSON: $response"
echo ""

# Check if direct GET was successful
if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    value=$(echo "$response" | jq -r '.data.value')
    echo "✅ Direct shard GET operation successful"
    echo "Retrieved value: $value"
    
    if [ "$value" = "shard_direct_value" ]; then
        echo "✅ Value matches expected result from direct PUT"
    else
        echo "⚠️  Value doesn't match expected result"
    fi
else
    echo "❌ Direct shard GET operation failed"
    echo "Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
fi

echo ""
echo "Note: This operation bypasses the router and reads directly from shard 1" 