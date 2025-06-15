#!/bin/bash

# High-performance Python Router startup script for KV-Raft

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ROUTER_DIR="$PROJECT_ROOT/router"

echo "Starting Python Router for KV-Raft..."

# Check if Python 3.8+ is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
REQUIRED_VERSION="3.8"

if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)"; then
    echo "Error: Python 3.8+ is required. Found Python $PYTHON_VERSION"
    exit 1
fi

echo "Using Python $PYTHON_VERSION"

# Check network connectivity
echo "Checking network connectivity..."
if ! curl -s --connect-timeout 5 https://pypi.org > /dev/null; then
    echo "Warning: Cannot reach PyPI (https://pypi.org)"
    echo "This might cause package installation issues."
    echo "Please check your internet connection or try again later."
fi

# Change to router directory
cd "$ROUTER_DIR"

# Check if virtual environment exists, create if not
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install/upgrade dependencies
echo "Installing dependencies..."

# Check if requirements.txt exists
if [ ! -f "requirements.txt" ]; then
    echo "Error: requirements.txt not found in $ROUTER_DIR"
    exit 1
fi

# Try to install with retries and better error handling
echo "Upgrading pip..."
if ! pip install --upgrade pip --timeout 60 --retries 3; then
    echo "Warning: Failed to upgrade pip, continuing with current version..."
fi

echo "Installing Python dependencies..."
if ! pip install -r requirements.txt --timeout 60 --retries 3; then
    echo "Error: Failed to install dependencies. Trying alternative approaches..."
    
    # Try installing packages individually with more retries
    echo "Attempting to install packages individually..."
    while IFS= read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^#.*$ ]] && continue
        
        echo "Installing $package..."
        if ! pip install "$package" --timeout 120 --retries 5; then
            echo "Warning: Failed to install $package, but continuing..."
        fi
    done < requirements.txt
    
    echo "Dependency installation completed with warnings. Checking if router can start..."
fi

# Verify critical dependencies are available
echo "Verifying critical dependencies..."
python3 -c "
import sys
missing = []
try:
    import aiohttp
except ImportError:
    missing.append('aiohttp')
try:
    import mmh3
except ImportError:
    missing.append('mmh3')

if missing:
    print(f'Missing dependencies: {missing}')
    print('Router may not work properly without these packages.')
    sys.exit(1)
else:
    print('✓ All critical dependencies are available')
"

# Parse command line arguments
PORT=3000
SHARD_PORTS="8011,8021,8031"
LOG_LEVEL="INFO"

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --shard-ports)
            SHARD_PORTS="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --port PORT              HTTP port to listen on (default: 3000)"
            echo "  --shard-ports PORTS      Comma-separated shard ports (default: 8011,8021,8031)"
            echo "  --log-level LEVEL        Log level: DEBUG, INFO, WARNING, ERROR (default: INFO)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Starting Python router on port $PORT..."
echo "Shard ports: $SHARD_PORTS"
echo "Log level: $LOG_LEVEL"

# Start the Python router
exec python3 router.py --port "$PORT" --shard-ports "$SHARD_PORTS" --log-level "$LOG_LEVEL" 