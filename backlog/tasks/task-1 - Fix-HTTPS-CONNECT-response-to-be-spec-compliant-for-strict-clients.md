---
id: TASK-1
title: Fix HTTPS CONNECT response to be spec-compliant for strict clients
status: To Do
assignee: []
created_date: '2026-05-16 07:52'
labels:
  - bug
  - https
  - proxy
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

`pkg/proxy/proxy.go` HttpsProxy.ServeHTTP calls `w.WriteHeader(http.StatusOK)` *before* hijacking the connection. Go's `net/http` then writes a full HTTP response with `Date:` and `Transfer-Encoding: chunked` headers — both of which are invalid for a CONNECT response. The proxy currently emits:

```
HTTP/1.1 200 OK\r\n
Date: <date>\r\n
Transfer-Encoding: chunked\r\n
\r\n
```

## Impact

Tolerant clients (curl) ignore the extra headers and the tunnel works. Strict clients reject the response — observed with **bun's fetch** HTTPS-over-CONNECT parser, which aborts within ~240ms with `InvalidHTTPResponse`. Discovered while running the Claude Code Telegram plugin (bun-based MCP server) through this proxy: every HTTPS request to `api.telegram.org` failed, even though the same proxy works fine for curl.

## Fix

Hijack the underlying TCP connection *first*, then write the spec-minimal CONNECT response directly to the raw socket — bypassing `ResponseWriter` entirely:

```
HTTP/1.1 200 Connection established\r\n\r\n
```

Also: replace the two `panic()` calls on hijack failure with graceful error returns that close `targetConn` so the proxy doesn't crash on a single misbehaving request and doesn't leak the upstream connection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CONNECT response emitted by the proxy is exactly `HTTP/1.1 200 Connection established\r\n\r\n` with no other headers — verified with `printf 'CONNECT host:443 HTTP/1.1\r\nHost: host:443\r\n\r\n' | nc -w 2 127.0.0.1 <port> | od -c`
- [ ] #2 `hj.Hijack()` is called before any byte of response is written
- [ ] #3 Hijack-failure path does not panic: it logs the error, closes `targetConn`, and returns
- [ ] #4 Regression: `curl -x http://127.0.0.1:<port> https://example.com` still succeeds
- [ ] #5 bun fetch through the proxy succeeds: `HTTPS_PROXY=http://127.0.0.1:<port> bun -e 'const r=await fetch("https://api.telegram.org"); console.log(r.status)'` prints a non-error status (200/404/etc, not a thrown exception)
- [ ] #6 `go build ./...`, `go vet ./...`, and `go test ./...` all pass
<!-- AC:END -->
