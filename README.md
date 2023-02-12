HTTP over SOCKS proxy
=========

Simple golang written http-over-socks proxy inspired by https://github.com/oyyd/http-proxy-to-socks.

Usage:
```
  -port string
    	Port to listen (prepended by colon), i.e. :8080 (default ":8080")
  -socks string
    	SOCKS5 proxy url, i.e. socks://127.0.0.1:1080
  -trace
    	Enable network tracing
  -verbose
    	Enable debug logging
```
