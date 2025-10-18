# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o auth-bridge ./cmd/server

# Runtime stage
FROM gcr.io/distroless/base-debian12
WORKDIR /app

COPY --from=builder /app/auth-bridge /usr/local/bin/auth-bridge

EXPOSE 8081

ENTRYPOINT ["/usr/local/bin/auth-bridge"]
