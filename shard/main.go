// KV-Raft: Distributed Key-Value Store with Raft Consensus
// Inspired by: https://github.com/aemirbosnak/distributed-key-value-store


package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/hashicorp/raft"
	raftboltdb "github.com/hashicorp/raft-boltdb/v2"

	"kv-raft/fsm"
)

// UnifiedServer combines data server and config server functionality
type UnifiedServer struct {
	raft     *raft.Raft
	server   *Server
	fsm      raft.FSM
	shardID  int
	knownShards map[int]string // shardID -> leader address mapping
}

const (
	tcpTimeout    = 1 * time.Second
	snapInterval  = 30 * time.Second
	snapThreshold = 1000
)

var (
	nodeID   = flag.String("node_id", "node_1", "raft node id")
	port     = flag.Int("port", 8001, "http port")
	raftaddr = flag.String("raft_addr", "localhost:18001", "raft address")
	shardID  = flag.Int("shard_id", 1, "shard id")
	storedir = flag.String("store_dir", "", "db dir")
	peerShards = flag.String("peer_shards", "", "comma-separated list of peer shard addresses for broadcasting (e.g., localhost:8011,localhost:8021)")
)

func NewUnifiedServer(raft *raft.Raft, fsm raft.FSM, shardID int) *UnifiedServer {
	server := New(raft, fsm)
	return &UnifiedServer{
		raft:        raft,
		server:      server,
		fsm:         fsm,
		shardID:     shardID,
		knownShards: make(map[int]string),
	}
}

// Data server handlers (original functionality)
func (us *UnifiedServer) GetHandler(w http.ResponseWriter, r *http.Request) {
	us.server.GetHandler(w, r)
}

func (us *UnifiedServer) PutHandler(w http.ResponseWriter, r *http.Request) {
	us.server.PutHandler(w, r)
}

func (us *UnifiedServer) DeleteHandler(w http.ResponseWriter, r *http.Request) {
	us.server.DeleteHandler(w, r)
}

// Config server handlers (merged from manager/main.go)
func (us *UnifiedServer) ConfigHandler(w http.ResponseWriter, r *http.Request) {
	log.Println("[HTTP] config is requested")
	log.Printf("[DEBUG] ConfigHandler called for shard %d", us.shardID)

	// Build shards map by querying the actual Raft cluster configuration
	allShards := make(map[int]string)
	
	// Get the current Raft configuration
	future := us.raft.GetConfiguration()
	if err := future.Error(); err != nil {
		log.Printf("Failed to get Raft configuration: %v", err)
		// Fallback to known shards
		for shardID, address := range us.knownShards {
			allShards[shardID] = address
		}
		// Add current shard
		allShards[us.shardID] = fmt.Sprintf("shard%d:%d", us.shardID, 8000+us.shardID*10+1)
		log.Printf("Using fallback configuration: %d shards", len(allShards))
	} else {
		log.Printf("Successfully got Raft configuration with %d servers", len(future.Configuration().Servers))
		// Process all servers in the Raft cluster
		for _, server := range future.Configuration().Servers {
			log.Printf("Processing server: ID=%s, Address=%s", server.ID, server.Address)
			// Extract shard ID from server ID (assuming server ID matches shard ID)
			if shardID, err := strconv.Atoi(string(server.ID)); err == nil {
				// Convert Raft address to HTTP address
				httpAddr := convertRaftToHTTPAddress(string(server.Address))
				// Normalize to use Docker service names
				normalizedAddr := normalizeShardAddress(shardID, httpAddr)
				allShards[shardID] = normalizedAddr
				log.Printf("Added shard %d with address %s", shardID, normalizedAddr)
			} else {
				log.Printf("Failed to parse server ID %s as integer: %v", server.ID, err)
			}
		}
		log.Printf("Final configuration: %d shards", len(allShards))
	}

	response := APIResponse{
		Success: true,
		Message: "Configuration retrieved successfully",
		Data: map[string]interface{}{
			"shardCount": len(allShards),
			"shards":     allShards,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func (us *UnifiedServer) AddShardHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ShardID      string `json:"shardID"`
		ShardAddress string `json:"shardAddress"`
	}
	
	// Try to parse JSON body first, fallback to form data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			WriteJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to form data for backward compatibility
		req.ShardID = r.FormValue("shardID")
		req.ShardAddress = r.FormValue("shardAddress")
	}

	if req.ShardID == "" || req.ShardAddress == "" {
		WriteJSONError(w, http.StatusBadRequest, "ShardID and ShardAddress are required")
		return
	}

	shardIDInt, err := strconv.Atoi(req.ShardID)
	if err != nil {
		WriteJSONError(w, http.StatusBadRequest, "Invalid shard ID format")
		return
	}

	// Normalize address to use Docker service name for consistency
	normalizedAddress := normalizeShardAddress(shardIDInt, req.ShardAddress)
	
	// Update local knowledge
	us.knownShards[shardIDInt] = normalizedAddress
	
	// Broadcast to other known shards
	us.broadcastShardInfo(shardIDInt, normalizedAddress)

	log.Printf("Added shard %d with address %s", shardIDInt, req.ShardAddress)
	
	response := APIResponse{
		Success: true,
		Message: "Shard added successfully",
		Data: map[string]interface{}{
			"shardID":      shardIDInt,
			"shardAddress": req.ShardAddress,
		},
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func (us *UnifiedServer) NewLeaderHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ShardID      string `json:"shardID"`
		ShardAddress string `json:"shardAddress"`
	}
	
	// Try to parse JSON body first, fallback to form data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			WriteJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to form data for backward compatibility
		req.ShardID = r.FormValue("shardID")
		req.ShardAddress = r.FormValue("shardAddress")
	}

	if req.ShardID == "" || req.ShardAddress == "" {
		WriteJSONError(w, http.StatusBadRequest, "ShardID and ShardAddress are required")
		return
	}

	shardIDInt, err := strconv.Atoi(req.ShardID)
	if err != nil {
		WriteJSONError(w, http.StatusBadRequest, "Invalid shard ID format")
		return
	}

	// Process the new leader info
	log.Printf("New leader address: %s, shard ID: %d", req.ShardAddress, shardIDInt)

	// Normalize address to use Docker service name for consistency
	normalizedAddress := normalizeShardAddress(shardIDInt, req.ShardAddress)
	
	// Update local knowledge
	us.knownShards[shardIDInt] = normalizedAddress
	
	// Broadcast to other known shards
	us.broadcastShardInfo(shardIDInt, req.ShardAddress)

	response := APIResponse{
		Success: true,
		Message: "Leader information updated successfully",
		Data: map[string]interface{}{
			"shardID":      shardIDInt,
			"shardAddress": req.ShardAddress,
		},
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// Raft handlers
func (us *UnifiedServer) RaftJoin(w http.ResponseWriter, r *http.Request) {
	us.server.RaftJoin(w, r)
}

func (us *UnifiedServer) RaftStatus(w http.ResponseWriter, r *http.Request) {
	us.server.RaftStatus(w, r)
}

func (us *UnifiedServer) RaftLeave(w http.ResponseWriter, r *http.Request) {
	us.server.RaftLeave(w, r)
}

// broadcastShardInfo sends shard information to all known peer shards
func (us *UnifiedServer) broadcastShardInfo(shardID int, address string) {
	for peerShardID, peerAddress := range us.knownShards {
		if peerShardID == us.shardID {
			continue // Don't broadcast to self
		}
		
		go func(peerAddr string) {
			url := fmt.Sprintf("http://%s/newleader", peerAddr)
			data := fmt.Sprintf("shardID=%d&shardAddress=%s", shardID, address)
			
			resp, err := http.Post(url, "application/x-www-form-urlencoded", 
				strings.NewReader(data))
			if err != nil {
				log.Printf("Failed to broadcast to %s: %v", peerAddr, err)
				return
			}
			defer resp.Body.Close()
		}(peerAddress)
	}
}

// LeaderObserver monitors leadership changes and broadcasts to peer shards
func (us *UnifiedServer) LeaderObserver() {
	go func() {
		lastAddress := us.raft.Leader()
		for {
			currentAddress := us.raft.Leader()
			if currentAddress != lastAddress {
				lastAddress = currentAddress

				// Check if this node is the leader
				if us.raft.State() == raft.Leader {
					log.Printf("Became leader for shard %d, broadcasting to peers", us.shardID)
					
					// Use Docker service name instead of IP address for consistency
					httpAddress := fmt.Sprintf("shard%d:%d", us.shardID, 8000+us.shardID*10+1)
					
					// Broadcast to all known shards
					us.broadcastShardInfo(us.shardID, httpAddress)
				}
			}
			time.Sleep(1 * time.Second)
		}
	}()
}

// convertRaftToHTTPAddress converts raft address (e.g., localhost:18001) to HTTP address (localhost:8001)
func convertRaftToHTTPAddress(raftAddr string) string {
	parts := strings.Split(raftAddr, ":")
	if len(parts) != 2 {
		return raftAddr
	}
	
	port, err := strconv.Atoi(parts[1])
	if err != nil {
		return raftAddr
	}
	
	httpPort := port - 10000
	return fmt.Sprintf("%s:%d", parts[0], httpPort)
}

// initializePeerShards parses the peer_shards flag and initializes known shards
func (us *UnifiedServer) initializePeerShards(peerShardsStr string) {
	if peerShardsStr == "" {
		return
	}
	
	peers := strings.Split(peerShardsStr, ",")
	for _, peer := range peers {
		peer = strings.TrimSpace(peer)
		if peer != "" {
			// Extract shard ID from the address format (e.g., shard2:8021 -> shard ID 2)
			peerShardID := extractShardIDFromAddress(peer)
			if peerShardID > 0 && peerShardID != us.shardID {
				us.knownShards[peerShardID] = peer
				log.Printf("Added peer shard %d at %s", peerShardID, peer)
			}
		}
	}
}

// extractShardIDFromAddress extracts shard ID from address like "shard2:8021" or "localhost:8021"
func extractShardIDFromAddress(address string) int {
	parts := strings.Split(address, ":")
	if len(parts) != 2 {
		return 0
	}
	
	host := parts[0]
	port := parts[1]
	
	// Try to extract from hostname first (e.g., "shard2" -> 2)
	if strings.HasPrefix(host, "shard") {
		shardIDStr := strings.TrimPrefix(host, "shard")
		if shardID, err := strconv.Atoi(shardIDStr); err == nil {
			return shardID
		}
	}
	
	// Fallback: extract from port (e.g., "8021" -> 2, "8031" -> 3)
	if portNum, err := strconv.Atoi(port); err == nil {
		if portNum >= 8011 && portNum <= 8099 {
			// Extract shard ID from port pattern: 80X1 -> X
			return (portNum - 8001) / 10
		}
	}
	
	return 0
}

// normalizeShardAddress converts any address format to Docker service name format
func normalizeShardAddress(shardID int, address string) string {
	// If it's already in the correct format (shardX:port), return as-is
	expectedServiceName := fmt.Sprintf("shard%d:", shardID)
	if strings.HasPrefix(address, expectedServiceName) {
		return address
	}
	
	// Extract port from the address
	parts := strings.Split(address, ":")
	if len(parts) == 2 {
		// Use the expected port for this shard
		expectedPort := 8000 + shardID*10 + 1
		return fmt.Sprintf("shard%d:%d", shardID, expectedPort)
	}
	
	// Fallback: construct the expected address
	expectedPort := 8000 + shardID*10 + 1
	return fmt.Sprintf("shard%d:%d", shardID, expectedPort)
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	flag.Parse()

	dir := *storedir
	if dir != "" {
		log.Println("Using existing store_dir: ", dir)
	} else {
		log.Println("Creating temp dir for raft")
		tempDir, err := os.MkdirTemp("", "kv_raft_")
		if err != nil {
			log.Fatalln("Failed to create temp dir")
		}
		defer os.RemoveAll(tempDir)
		log.Printf("Created temp dir %s", tempDir)
		dir = tempDir
	}

	raftConfig := raft.DefaultConfig()
	raftConfig.LocalID = raft.ServerID(*nodeID)
	raftConfig.SnapshotInterval = snapInterval
	raftConfig.SnapshotThreshold = snapThreshold

	fsmStore := fsm.NewFSM()

	// Raft configuration
	store, err := raftboltdb.NewBoltStore(filepath.Join(dir, "raft.db"))
	if err != nil {
		log.Fatal(err)
	}

	cacheStore, err := raft.NewLogCache(256, store)
	if err != nil {
		log.Fatal(err)
	}

	snapshotStore, err := raft.NewFileSnapshotStore(dir, 1, os.Stdout)
	if err != nil {
		log.Fatal(err)
	}

	tcpAddr, err := net.ResolveTCPAddr("tcp", *raftaddr)
	if err != nil {
		log.Fatal(err)
	}

	transport, err := raft.NewTCPTransport(*raftaddr, tcpAddr, 3, tcpTimeout, os.Stdout)
	if err != nil {
		log.Fatal(err)
	}

	raftServer, err := raft.NewRaft(raftConfig, fsmStore, cacheStore, store, snapshotStore, transport)
	if err != nil {
		log.Fatal(err)
	}

	// Only bootstrap cluster on shard 1, others will join via /raft/join
	if *shardID == 1 {
		log.Printf("Shard 1: Bootstrapping new Raft cluster")
		raftServer.BootstrapCluster(raft.Configuration{
			Servers: []raft.Server{
				{
					ID:      raft.ServerID(*nodeID),
					Address: transport.LocalAddr(),
				},
			},
		})
	} else {
		log.Printf("Shard %d: Waiting to join existing Raft cluster", *shardID)
	}

	// Create unified server
	unifiedServer := NewUnifiedServer(raftServer, fsmStore, *shardID)
	
	// Initialize peer shards
	unifiedServer.initializePeerShards(*peerShards)
	
	// Start leader observer
	unifiedServer.LeaderObserver()

	// Data operation endpoints
	http.HandleFunc("/get", unifiedServer.GetHandler)
	http.HandleFunc("/put", unifiedServer.PutHandler)
	http.HandleFunc("/delete", unifiedServer.DeleteHandler)

	// Config operation endpoints (merged from config server)
	http.HandleFunc("/config", unifiedServer.ConfigHandler)
	http.HandleFunc("/addshard", unifiedServer.AddShardHandler)
	http.HandleFunc("/newleader", unifiedServer.NewLeaderHandler)

	// Raft management endpoints
	http.HandleFunc("/raft/join", unifiedServer.RaftJoin)
	http.HandleFunc("/raft/status", unifiedServer.RaftStatus)
	http.HandleFunc("/raft/leave", unifiedServer.RaftLeave)

	log.Printf("Unified server (shard %d) listening on port %d", *shardID, *port)
	err = http.ListenAndServe(fmt.Sprintf(":%d", *port), nil)
	if err != nil {
		fmt.Printf("Server error: %v\n", err)
	}
}
