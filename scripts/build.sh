#!/bin/sh
set -eu

mkdir -p dist
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o dist/radioko-leka-linux-amd64 ./cmd/radioko-leka
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o dist/radioko-leka-darwin-amd64 ./cmd/radioko-leka
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o dist/radioko-leka-darwin-arm64 ./cmd/radioko-leka
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o dist/radioko-leka-windows-amd64.exe ./cmd/radioko-leka

printf '%s\n' "Builds disponibles dans dist/"
