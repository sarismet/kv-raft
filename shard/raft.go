// KV-Raft: Raft consensus implementation for distributed key-value store
// Inspired by: https://github.com/aemirbosnak/distributed-key-value-store


package main

import (
	"encoding/json"
	"fmt"
	"github.com/hashicorp/raft"
	"net/http"
)

type JoinRequest struct {
	NodeID string `json:"nodeid"`
	Addr   string `json:"addr"`
}

type LeaveRequest struct {
	NodeID string `json:"nodeid"`
}

func (s Server) RaftJoin(w http.ResponseWriter, r *http.Request) {
	var req JoinRequest
	
	// Try to parse JSON body first, fallback to form data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to form data for backward compatibility
		req.NodeID = r.FormValue("nodeid")
		req.Addr = r.FormValue("addr")
	}

	if req.NodeID == "" || req.Addr == "" {
		writeJSONError(w, http.StatusBadRequest, "NodeID and address are required")
		return
	}

	if s.raft.State() != raft.Leader {
		writeJSONError(w, http.StatusBadRequest, "This node is not the leader")
		return
	}

	configFuture := s.raft.GetConfiguration()
	if err := configFuture.Error(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Failed to get raft configuration")
		return
	}

	f := s.raft.AddVoter(raft.ServerID(req.NodeID), raft.ServerAddress(req.Addr), 0, 0)
	if f.Error() != nil {
		writeJSONError(w, http.StatusInternalServerError, "Failed to add voter: "+f.Error().Error())
		return
	}

	response := APIResponse{
		Success: true,
		Message: "Node joined successfully",
		Data: map[string]string{
			"nodeid": req.NodeID,
			"addr":   req.Addr,
		},
	}
	writeJSONResponse(w, http.StatusOK, response)
}

func (s Server) RaftStatus(w http.ResponseWriter, r *http.Request) {
	stats := s.raft.Stats()
	
	response := APIResponse{
		Success: true,
		Message: "Raft status retrieved successfully",
		Data:    stats,
	}
	writeJSONResponse(w, http.StatusOK, response)
}

func (s Server) RaftLeave(w http.ResponseWriter, r *http.Request) {
	var req LeaveRequest
	
	// Try to parse JSON body first, fallback to form data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to form data for backward compatibility
		req.NodeID = r.FormValue("nodeid")
	}

	if req.NodeID == "" {
		writeJSONError(w, http.StatusBadRequest, "NodeID is required")
		return
	}

	if s.raft.State() != raft.Leader {
		writeJSONError(w, http.StatusBadRequest, "This node is not the leader")
		return
	}

	configFuture := s.raft.GetConfiguration()
	if err := configFuture.Error(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Failed to get raft configuration")
		return
	}

	future := s.raft.RemoveServer(raft.ServerID(req.NodeID), 0, 0)
	if err := future.Error(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to remove node %s: %s", req.NodeID, err.Error()))
		return
	}

	response := APIResponse{
		Success: true,
		Message: "Node removed successfully",
		Data: map[string]string{
			"nodeid": req.NodeID,
		},
	}
	writeJSONResponse(w, http.StatusOK, response)
}
