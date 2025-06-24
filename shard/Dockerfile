# Build stage
FROM golang:1.24.4-alpine AS builder

WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o shard-server .

# Final stage
FROM alpine:latest

# Install curl for health checks
RUN apk --no-cache add curl

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/shard-server .

# Make it executable
RUN chmod +x shard-server

# Expose ports
EXPOSE 8011 8021 8031 18011 18021 18031
