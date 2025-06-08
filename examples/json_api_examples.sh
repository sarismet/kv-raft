#!/bin/bash

echo "=== KV-Raft JSON API Examples ==="
echo "Architecture: 3 shards forming 1 Raft cluster"
echo ""

# Base URL for the router
ROUTER_URL="http://localhost:3000"

echo "1. Check router status:"
curl -s "$ROUTER_URL/status" | jq '.'
echo ""

echo "2. PUT operation (using query parameters):"
curl -s "$ROUTER_URL/put?key=user1&val=john_doe" | jq '.'
echo ""

echo "3. PUT operation (using JSON body):"
curl -s -H "Content-Type: application/json" \
     -d '{"key":"user2","val":"jane_smith"}' \
     "$ROUTER_URL/put" | jq '.'
echo ""

echo "4. GET operation:"
curl -s "$ROUTER_URL/get?key=user1" | jq '.'
echo ""

echo "5. GET operation for non-existent key:"
curl -s "$ROUTER_URL/get?key=nonexistent" | jq '.'
echo ""

echo "6. DELETE operation:"
curl -s -X DELETE "$ROUTER_URL/delete?key=user2" | jq '.'
echo ""

echo "7. Verify deletion:"
curl -s "$ROUTER_URL/get?key=user2" | jq '.'
echo ""

echo "=== Direct Shard API Examples ==="
echo ""

# Direct shard access (assuming shard 1 is running on port 8011)
SHARD_URL="http://localhost:8011"

echo "8. Get shard configuration:"
curl -s "$SHARD_URL/config" | jq '.'
echo ""

echo "9. Get raft status:"
curl -s "$SHARD_URL/raft/status" | jq '.'
echo ""

echo "10. PUT directly to shard (JSON):"
curl -s -H "Content-Type: application/json" \
     -d '{"key":"direct_key","val":"direct_value"}' \
     "$SHARD_URL/put" | jq '.'
echo ""

echo "11. GET directly from shard:"
curl -s "$SHARD_URL/get?key=direct_key" | jq '.'
echo ""

echo "=== Error Examples ==="
echo ""

echo "12. PUT without required parameters (using POST method):"
response=$(curl -s -X POST "$ROUTER_URL/put")
if echo "$response" | jq empty 2>/dev/null; then
    echo "$response" | jq '.'
else
    echo "Not valid JSON: $response"
fi
echo ""

echo "13. GET without key parameter:"
curl -s "$ROUTER_URL/get" | jq '.'
echo ""

echo "14. Invalid JSON body:"
response=$(curl -s -X POST -H "Content-Type: application/json" \
     -d '{"invalid": json}' \
     "$SHARD_URL/put")
if echo "$response" | jq empty 2>/dev/null; then
    echo "$response" | jq '.'
else
    echo "Not valid JSON: $response"
fi
echo ""

echo "=== All examples completed ===" 