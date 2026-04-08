#!/bin/bash
# 编译 sync-nodes for amd64 和 arm64

VERSION="1.2.1"
BUILD_TIME=$(date -u +"%Y-%m-%d")

echo "编译 sync-nodes v${VERSION}"
echo ""

# amd64
echo "编译 amd64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -trimpath \
  -ldflags="-s -w -buildid= -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME}" \
  -o sync-nodes-linux-amd64 main.go

# arm64
echo "编译 arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
  -trimpath \
  -ldflags="-s -w -buildid= -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME}" \
  -o sync-nodes-linux-arm64 main.go

echo ""
echo "编译完成！"
ls -lh sync-nodes-linux-*
