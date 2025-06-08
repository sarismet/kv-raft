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

	// Build shards map with proper structure
	allShards := make(map[int]string)
	
	// Add current shard info (convert raft address to HTTP address)
	currentLeaderAddr := string(us.raft.Leader())
	if currentLeaderAddr != "" {
		httpAddr := convertRaftToHTTPAddress(currentLeaderAddr)
		allShards[us.shardID] = httpAddr
	}
	
	// Add known shards info
	for shardID, address := range us.knownShards {
		allShards[shardID] = address
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

	// Update local knowledge
	us.knownShards[shardIDInt] = req.ShardAddress
	
	// Broadcast to other known shards
	us.broadcastShardInfo(shardIDInt, req.ShardAddress)

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

	// Update local knowledge
	us.knownShards[shardIDInt] = req.ShardAddress
	
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
					
					// Convert raft address to HTTP address (subtract 10000 from port)
					httpAddress := convertRaftToHTTPAddress(string(currentAddress))
					
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
	for i, peer := range peers {
		peer = strings.TrimSpace(peer)
		if peer != "" {
			// Assign shard IDs based on order (this is a simple approach)
			// In production, you might want a more sophisticated shard ID assignment
			peerShardID := i + 1
			if peerShardID == us.shardID {
				peerShardID = i + 2 // Skip our own shard ID
			}
			us.knownShards[peerShardID] = peer
			log.Printf("Added peer shard %d at %s", peerShardID, peer)
		}
	}
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

	raftServer.BootstrapCluster(raft.Configuration{
		Servers: []raft.Server{
			{
				ID:      raft.ServerID(*nodeID),
				Address: transport.LocalAddr(),
			},
		},
	})

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
