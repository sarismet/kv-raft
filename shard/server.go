// KV-Raft: Server implementation for distributed key-value store
// Inspired by: https://github.com/aemirbosnak/distributed-key-value-store


package main

import (
	"github.com/hashicorp/raft"
)

type Server struct {
	raft *raft.Raft
	fsm  raft.FSM
}

func New(raft *raft.Raft, fsm raft.FSM) *Server {
	return &Server{
		raft: raft,
		fsm:  fsm,
	}
}
