package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"kv-raft/fsm"
)

// Response structures for consistent JSON responses
type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

type GetResponse struct {
	Success bool   `json:"success"`
	Key     string `json:"key"`
	Value   string `json:"value"`
	Error   string `json:"error,omitempty"`
}

type PutRequest struct {
	Key   string `json:"key"`
	Value string `json:"val"`
}

type DeleteRequest struct {
	Key string `json:"key"`
}

func WriteJSONResponse(w http.ResponseWriter, statusCode int, response interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(response)
}

func WriteJSONError(w http.ResponseWriter, statusCode int, message string) {
	response := APIResponse{
		Success: false,
		Error:   message,
	}
	WriteJSONResponse(w, statusCode, response)
}

// Keep the lowercase versions for internal use
func writeJSONResponse(w http.ResponseWriter, statusCode int, response interface{}) {
	WriteJSONResponse(w, statusCode, response)
}

func writeJSONError(w http.ResponseWriter, statusCode int, message string) {
	WriteJSONError(w, statusCode, message)
}

func (s *Server) PutHandler(w http.ResponseWriter, r *http.Request) {
	var req PutRequest

	// Try to parse JSON body first, fallback to form data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to form data for backward compatibility
		r.ParseForm()
		req.Key = r.Form.Get("key")
		req.Value = r.Form.Get("val")
	}

	if req.Key == "" || req.Value == "" {
		writeJSONError(w, http.StatusBadRequest, "Key and value are required")
		return
	}

	log.Printf("[HTTP-PUT] key %s was put into this node", req.Key)

	payload := fsm.Payload{
		OP:    fsm.PUT,
		Key:   req.Key,
		Value: req.Value,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Failed to marshal payload")
		return
	}

	applyFuture := s.raft.Apply(data, 500*time.Millisecond)
	if err := applyFuture.Error(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Raft apply failed: "+err.Error())
		return
	}

	_, ok := applyFuture.Response().(*fsm.ApplyResponse)
	if !ok {
		writeJSONError(w, http.StatusInternalServerError, "Invalid raft response")
		return
	}

	response := APIResponse{
		Success: true,
		Message: "Key-value pair stored successfully",
		Data: map[string]string{
			"key":   req.Key,
			"value": req.Value,
		},
	}
	writeJSONResponse(w, http.StatusOK, response)
}

func (s *Server) GetHandler(w http.ResponseWriter, r *http.Request) {
	var key string

	// Try to get key from query parameter first, then from JSON body
	key = r.URL.Query().Get("key")
	if key == "" {
		r.ParseForm()
		key = r.Form.Get("key")
	}

	if key == "" {
		writeJSONError(w, http.StatusBadRequest, "Key parameter is required")
		return
	}

	fsmInstance, ok := s.fsm.(*fsm.FSM)
	if !ok {
		writeJSONError(w, http.StatusInternalServerError, "Failed to access FSM")
		return
	}

	value, err := fsmInstance.Get(key)
	if err != nil {
		response := GetResponse{
			Success: false,
			Key:     key,
			Error:   "Key not found",
		}
		writeJSONResponse(w, http.StatusNotFound, response)
		return
	}

	log.Printf("[HTTP-GET] key %s was found on this node", key)

	var valueStr string
	if str, ok := value.(string); ok {
		valueStr = str
	} else if bytes, ok := value.([]byte); ok {
		valueStr = string(bytes)
	} else {
		writeJSONError(w, http.StatusInternalServerError, "Failed to convert value")
		return
	}

	response := GetResponse{
		Success: true,
		Key:     key,
		Value:   valueStr,
	}
	writeJSONResponse(w, http.StatusOK, response)
}

func (s *Server) DeleteHandler(w http.ResponseWriter, r *http.Request) {
	var req DeleteRequest

	// Try to parse JSON body first, fallback to form/query data
	if r.Header.Get("Content-Type") == "application/json" {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSONError(w, http.StatusBadRequest, "Invalid JSON format")
			return
		}
	} else {
		// Fallback to query parameter or form data
		req.Key = r.URL.Query().Get("key")
		if req.Key == "" {
			r.ParseForm()
			req.Key = r.Form.Get("key")
		}
	}

	if req.Key == "" {
		writeJSONError(w, http.StatusBadRequest, "Key parameter is required")
		return
	}

	log.Printf("[HTTP-DELETE] key %s was deleted from this node", req.Key)

	payload := fsm.Payload{
		OP:  fsm.DEL,
		Key: req.Key,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Failed to marshal payload")
		return
	}

	applyFuture := s.raft.Apply(data, 500*time.Millisecond)
	if err := applyFuture.Error(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "Raft apply failed: "+err.Error())
		return
	}

	_, ok := applyFuture.Response().(*fsm.ApplyResponse)
	if !ok {
		writeJSONError(w, http.StatusInternalServerError, "Invalid raft response")
		return
	}

	response := APIResponse{
		Success: true,
		Message: "Key deleted successfully",
		Data: map[string]string{
			"key": req.Key,
		},
	}
	writeJSONResponse(w, http.StatusOK, response)
}
