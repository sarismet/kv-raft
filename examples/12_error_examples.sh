#!/bin/bash

echo "=== Error Examples ==="
echo ""

ROUTER_URL="http://localhost:3000"
SHARD_URL="http://localhost:8011"

echo "1. PUT without required parameters (using POST method):"
echo "URL: $ROUTER_URL/put"
echo "Method: POST (no parameters)"
response=$(curl -s -X POST "$ROUTER_URL/put")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo ""

echo "2. GET without key parameter:"
echo "URL: $ROUTER_URL/get"
response=$(curl -s "$ROUTER_URL/get")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo ""

echo "3. Invalid JSON body to shard:"
echo "URL: $SHARD_URL/put"
echo "Method: POST"
echo "Body: {\"invalid\": json}"
response=$(curl -s -X POST -H "Content-Type: application/json" \
     -d '{"invalid": json}' \
     "$SHARD_URL/put")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo ""

echo "4. DELETE without key parameter:"
echo "URL: $ROUTER_URL/delete"
response=$(curl -s -X DELETE "$ROUTER_URL/delete")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo ""

echo "5. Request to non-existent endpoint:"
echo "URL: $ROUTER_URL/nonexistent"
response=$(curl -s "$ROUTER_URL/nonexistent")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo ""

echo "6. Wrong HTTP method for PUT (using GET instead of POST):"
echo "URL: $ROUTER_URL/put"
echo "Method: GET (should be POST)"
response=$(curl -s "$ROUTER_URL/put")
echo "Raw response: $response"
if echo "$response" | jq empty 2>/dev/null; then
    echo "Formatted: $(echo "$response" | jq '.')"
else
    echo "Formatted: Not valid JSON - $response"
fi
echo "" 