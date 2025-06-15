#!/usr/bin/env python3
"""
High-performance async router for KV-Raft distributed system.
Uses asyncio for green threads (similar to goroutines) and aiohttp for async HTTP operations.
"""

import asyncio
import argparse
import json
import logging
import sys
from typing import Dict, List, Optional, Tuple, Any
from urllib.parse import quote, unquote

import aiohttp
import mmh3  # MurmurHash3 implementation
from aiohttp import web, ClientSession, ClientTimeout
from aiohttp.web import Request, Response, json_response


# Constants
HASH_MODULO = 16384
DEFAULT_SHARD_PORTS = ["8011", "8021", "8031"]

# Global HTTP session for connection pooling and performance
http_session: Optional[ClientSession] = None


class APIResponse:
    """Structured API response for consistent JSON responses."""

    def __init__(self, success: bool, message: str = "", data: Any = None, error: str = ""):
        self.success = success
        self.message = message
        self.data = data
        self.error = error

    def to_dict(self) -> Dict[str, Any]:
        result = {"success": self.success}
        if self.message:
            result["message"] = self.message
        if self.data is not None:
            result["data"] = self.data
        if self.error:
            result["error"] = self.error
        return result


def json_error_response(status: int, message: str) -> Response:
    """Create a JSON error response."""
    response = APIResponse(success=False, error=message)
    return json_response(response.to_dict(), status=status)


def json_success_response(data: Any = None, message: str = "", status: int = 200) -> Response:
    """Create a JSON success response."""
    response = APIResponse(success=True, message=message, data=data)
    return json_response(response.to_dict(), status=status)


def hash_string_key(key: str) -> int:
    """Hash a string key using MurmurHash3."""
    return mmh3.hash64(key, signed=False)[0]


def get_shard_index_from_hash(hash_value: int, shard_count: int) -> int:
    """Get shard index from hash value."""
    if shard_count <= 0:
        raise ValueError("Shard count must be positive")

    reduced_hash = hash_value % HASH_MODULO
    bucket_size = HASH_MODULO // shard_count

    for i in range(shard_count):
        if reduced_hash < (i + 1) * bucket_size:
            return i

    return shard_count - 1


def get_shard_index_from_string_key(key: str, shard_count: int) -> int:
    """Get shard index from string key."""
    return get_shard_index_from_hash(hash_string_key(key), shard_count)


class RouterConfig:
    """Router configuration management."""

    def __init__(self, shard_ports: List[str]):
        self.shard_ports = shard_ports
        self._config_cache: Optional[Dict[str, Any]] = None
        self._cache_timestamp = 0
        self._cache_ttl = 30  # Cache TTL in seconds

    def get_shard_ports(self) -> List[str]:
        """Get list of shard ports."""
        return self.shard_ports if self.shard_ports else DEFAULT_SHARD_PORTS

    async def _fetch_config_from_shard(self, port: str) -> Optional[Dict[str, Any]]:
        """Fetch configuration from a specific shard."""
        try:
            port = port.strip()
            # Correctly form the URL using the service name if it's in the format 'shard1:8011'
            if ":" in port:
                host_port = port
            else:
                # This logic might need adjustment depending on how shard names are constructed.
                # Assuming a pattern like shard1, shard2 for ports 8011, 8021 etc.
                shard_num = (int(port) % 100) // 10
                host_port = f"shard{shard_num}:{port}"

            url = f"http://{host_port}/config"
            logging.info(f"Attempting to fetch config from {url}")

            async with http_session.get(url, timeout=ClientTimeout(total=5)) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    logging.info(f"Using shard at {host_port} for config")
                    return data
        except Exception as e:
            logging.debug(f"Failed to get config from port {port}: {e}")

        return None

    async def get_config(self) -> Optional[Dict[str, Any]]:
        """Get configuration from any available shard with caching."""
        current_time = asyncio.get_event_loop().time()

        if (self._config_cache and
            current_time - self._cache_timestamp < self._cache_ttl):
            return self._config_cache

        # Try each shard concurrently for better performance
        ports = self.get_shard_ports()
        tasks = [asyncio.create_task(self._fetch_config_from_shard(port)) for port in ports]

        first_successful_result = None
        try:
            # Use asyncio.as_completed to get the first successful response
            for coro in asyncio.as_completed(tasks):
                result = await coro
                if result and result.get("success"):
                    first_successful_result = result
                    break  # Found a working shard, no need to wait for others
        finally:
            # Cancel remaining tasks for efficiency
            for task in tasks:
                if not task.done():
                    task.cancel()

        if first_successful_result:
            self._config_cache = first_successful_result
            self._cache_timestamp = current_time
            return first_successful_result
        
        logging.error("Failed to get config from any shard")
        return None # Explicitly return None

    async def get_shard_count(self) -> int:
        """Get the number of shards."""
        config = await self.get_config()
        if not config:
            raise RuntimeError("Could not retrieve cluster configuration.")
        data = config.get("data", {})
        shard_count = data.get("shardCount")

        if shard_count is None:
            raise ValueError("shardCount not found in config response")

        return int(shard_count)

    async def get_shard_address(self, shard_id: int) -> str:
        """Get the address of a specific shard."""
        config = await self.get_config()
        if not config:
            raise RuntimeError("Could not retrieve cluster configuration.")
        data = config.get("data", {})
        shards = data.get("shards", {})

        leader_address = shards.get(str(shard_id))
        if not leader_address:
            raise ValueError(f"Shard {shard_id} not found in config")

        # Convert Raft address to HTTP address if needed
        if ":18" in leader_address:
            parts = leader_address.split(":")
            if len(parts) != 2:
                raise ValueError(f"Invalid leader address format: {leader_address}")

            try:
                port = int(parts[1])
                server_port = port - 10000
                return f"{parts[0]}:{server_port}"
            except ValueError as e:
                raise ValueError(f"Error parsing port: {e}")

        return leader_address


# Global router config
router_config: Optional[RouterConfig] = None


async def status_handler(request: Request) -> Response:
    """Handle status requests."""
    try:
        shard_count = await router_config.get_shard_count()
        if shard_count is None:
            return json_error_response(500, "Failed to determine shard count")
        return json_success_response(
            data={"shardCount": shard_count},
            message="Router status retrieved successfully"
        )
    except Exception as e:
        logging.error(f"Error getting shard count: {e}")
        return json_error_response(500, f"Error getting shard count: {str(e)}")


async def get_handler(request: Request) -> Response:
    """Handle GET requests."""
    try:
        # Get key from query parameters or form data
        key = request.query.get("key")
        if not key and request.content_type == "application/x-www-form-urlencoded":
            form_data = await request.post()
            key = form_data.get("key")

        if not key:
            return json_error_response(400, "Key parameter is required")

        # Decode URL-encoded key
        key = unquote(key)

        shard_count = await router_config.get_shard_count()
        shard_index = get_shard_index_from_string_key(key, shard_count)
        shard_address = await router_config.get_shard_address(shard_index + 1)

        # Forward request to appropriate shard
        server_url = f"http://{shard_address}/get?key={quote(key)}"

        async with http_session.get(server_url, timeout=ClientTimeout(total=10)) as resp:
            # Forward the response from the data server
            response_data = await resp.text()
            return Response(
                text=response_data,
                status=resp.status,
                content_type="application/json"
            )

    except Exception as e:
        logging.error(f"Error in get_handler: {e}")
        return json_error_response(500, f"Error contacting server node: {str(e)}")


async def put_handler(request: Request) -> Response:
    """Handle PUT requests."""
    try:
        # Get key and value from query parameters or form data
        key = request.query.get("key")
        value = request.query.get("val")

        if not key or not value:
            if request.content_type == "application/x-www-form-urlencoded":
                form_data = await request.post()
                key = key or form_data.get("key")
                value = value or form_data.get("val")

        if not key or not value:
            return json_error_response(400, "Key and value parameters are required")

        # Decode URL-encoded parameters
        key = unquote(key)
        value = unquote(value)

        shard_count = await router_config.get_shard_count()
        shard_index = get_shard_index_from_string_key(key, shard_count)
        shard_address = await router_config.get_shard_address(shard_index + 1)

        # Forward request to appropriate shard
        server_url = f"http://{shard_address}/put?key={quote(key)}&val={quote(value)}"

        async with http_session.post(server_url, timeout=ClientTimeout(total=10)) as resp:
            # Forward the response from the data server
            response_data = await resp.text()
            return Response(
                text=response_data,
                status=resp.status,
                content_type="application/json"
            )

    except Exception as e:
        logging.error(f"Error in put_handler: {e}")
        return json_error_response(500, f"Error contacting server node: {str(e)}")


async def delete_handler(request: Request) -> Response:
    """Handle DELETE requests."""
    try:
        # Get key from query parameters or form data
        key = request.query.get("key")
        if not key and request.content_type == "application/x-www-form-urlencoded":
            form_data = await request.post()
            key = form_data.get("key")

        if not key:
            return json_error_response(400, "Key parameter is required")

        # Decode URL-encoded key
        key = unquote(key)

        shard_count = await router_config.get_shard_count()
        shard_index = get_shard_index_from_string_key(key, shard_count)
        shard_address = await router_config.get_shard_address(shard_index + 1)

        # Forward request to appropriate shard
        server_url = f"http://{shard_address}/delete?key={quote(key)}"

        async with http_session.delete(server_url, timeout=ClientTimeout(total=10)) as resp:
            # Forward the response from the data server
            response_data = await resp.text()
            return Response(
                text=response_data,
                status=resp.status,
                content_type="application/json"
            )

    except Exception as e:
        logging.error(f"Error in delete_handler: {e}")
        return json_error_response(500, f"Error contacting server node: {str(e)}")


async def init_app() -> web.Application:
    """Initialize the web application."""
    app = web.Application()

    # Add routes
    app.router.add_get("/status", status_handler)
    app.router.add_get("/get", get_handler)
    app.router.add_post("/put", put_handler)
    app.router.add_delete("/delete", delete_handler)

    return app


async def create_http_session() -> ClientSession:
    """Create HTTP session with optimized settings."""
    connector = aiohttp.TCPConnector(
        limit=100,  # Total connection pool size
        limit_per_host=30,  # Max connections per host
        ttl_dns_cache=300,  # DNS cache TTL
        use_dns_cache=True,
        keepalive_timeout=30,
        enable_cleanup_closed=True
    )

    timeout = ClientTimeout(total=30, connect=5)

    return ClientSession(
        connector=connector,
        timeout=timeout,
        headers={"User-Agent": "KV-Raft-Router/1.0"}
    )


async def cleanup_session():
    """Cleanup HTTP session."""
    global http_session
    if http_session:
        await http_session.close()


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="High-performance KV-Raft Router")
    parser.add_argument(
        "--port",
        type=int,
        default=3000,
        help="HTTP port to listen on (default: 3000)"
    )
    parser.add_argument(
        "--shard-ports",
        type=str,
        default="8011,8021,8031",
        help="Comma-separated list of shard leader ports to query for config"
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )

    return parser.parse_args()


async def main():
    """Main application entry point."""
    global http_session, router_config

    args = parse_args()

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # Parse shard ports
    shard_ports = [port.strip() for port in args.shard_ports.split(",")]

    # Initialize global components
    http_session = await create_http_session()
    router_config = RouterConfig(shard_ports)

    logging.info("Starting router node for unified architecture")
    logging.info(f"Will query shards at ports: {shard_ports} for configuration")

    # Create and start the web application
    app = await init_app()

    try:
        # Start the server
        logging.info(f"Router listening on port: {args.port}")
        runner = web.AppRunner(app)
        await runner.setup()

        site = web.TCPSite(runner, "0.0.0.0", args.port)
        await site.start()

        # Keep the server running
        try:
            await asyncio.Future()  # Run forever
        except KeyboardInterrupt:
            logging.info("Shutting down...")

    finally:
        await cleanup_session()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("Router stopped by user")
    except Exception as e:
        logging.error(f"Fatal error: {e}")
        sys.exit(1)
