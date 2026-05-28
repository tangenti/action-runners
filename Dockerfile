# syntax=docker/dockerfile:1
FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY cmd/server/main.go ./cmd/server/main.go

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/server ./cmd/server

# -------------------------------------------------------
FROM scratch

COPY --from=builder /out/server /server

EXPOSE 8080

ENTRYPOINT ["/server"]
