Forward HTTP proxy
=========

Simple golang written HTTP proxy inspired by https://github.com/oyyd/http-proxy-to-socks.

Can be used as ordinal forward HTTP proxy and as HTTP-over-SOCKS proxy if `socks` parameter is specified.

Usage:
```
  -port string
    	Port to listen (prepended by colon), i.e. :8080 (default ":8080")
  -socks string
    	SOCKS5 proxy URL, i.e. socks://127.0.0.1:1080
  -trace
    	Enable network tracing
  -verbose
    	Enable debug logging
```

Links:
* https://eli.thegreenplace.net/2022/go-and-proxy-servers-part-1-http-proxies/
