HTTP over SOCKS proxy
=========

Simple golang written http-over-socks proxy inspired by https://github.com/oyyd/http-proxy-to-socks.

Usage:
```
  -port string
    	Port to listen (prepended by colon), i.e. :8080 (default ":8080")
  -trace
    	Enable network tracing
  -verbose
    	Enable debug logging
```

Proxy chain:
```
HTTP_PROXY=socks5://127.0.0.1:1080 go run main.go -port :8080 -verbose
curl -v -x http://127.0.0.1:8080 https://ifconfig.me
```
