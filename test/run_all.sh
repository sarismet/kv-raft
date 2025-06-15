#!/bin/bash

echo "🚀 Running All KV-Raft API Tests"
echo "=================================="
echo "Architecture: 3 shards forming 1 Raft cluster"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of test scripts in order
TESTS=(
    "01_router_status.sh"
    "02_put_query_params.sh"
    "03_put_json_body.sh"
    "04_get_operation.sh"
    "05_get_nonexistent.sh"
    "06_delete_operation.sh"
    "07_verify_deletion.sh"
    "08_shard_config.sh"
    "09_raft_status.sh"
    "10_direct_shard_put.sh"
    "11_direct_shard_get.sh"
)

# Function to run a test with error handling
run_test() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    if [[ -f "$script_path" ]]; then
        echo "📋 Running: $script"
        echo "----------------------------------------"
        chmod +x "$script_path"
        bash "$script_path"
        echo ""
        echo "✅ Completed: $script"
        echo ""
        echo "========================================"
        echo ""
    else
        echo "❌ Script not found: $script_path"
        echo ""
    fi
}

# Check if router and shards are running
echo "🔍 Pre-flight checks..."
echo ""

# Check router
if curl -s "http://localhost:3000/status" >/dev/null 2>&1; then
    echo "✅ Router is running on port 3000"
else
    echo "❌ Router is not running on port 3000"
    echo "   Please start the router first:"
    echo "   ./scripts/run_python_router.sh"
    echo ""
fi

# Check shards
shard_count=0
for shard in 1 2 3; do
    port="80${shard}1"
    if curl -s "http://localhost:$port/config" >/dev/null 2>&1; then
        echo "✅ Shard $shard is running on port $port"
        ((shard_count++))
    else
        echo "❌ Shard $shard is not running on port $port"
    fi
done

if [[ $shard_count -eq 3 ]]; then
    echo "✅ All shards are running"
else
    echo "❌ Only $shard_count/3 shards are running"
    echo "   Please start the shards first:"
    echo "   ./scripts/run_shards.sh"
fi

echo ""
echo "========================================"
echo ""

# Ask user if they want to continue
read -p "Do you want to continue with the tests? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting..."
    exit 0
fi

echo ""

# Run all tests
for test in "${TESTS[@]}"; do
    run_test "$test"
    
    # Optional: pause between tests
    if [[ "$1" == "--pause" ]]; then
        read -p "Press Enter to continue to next test..." -r
        echo ""
    fi
done

echo "🎉 All tests completed!"
echo ""
echo "📊 Summary:"
echo "  - Total tests run: ${#TESTS[@]}"
echo "  - Check individual outputs above for results"
echo ""
echo "💡 Tips:"
echo "  - Run individual scripts for focused testing"
echo "  - Use --pause flag to pause between tests"
echo "  - Check logs/ directory for detailed server logs" 