package proxy

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"net/http/httputil"

	"github.com/dddpaul/http-over-socks-proxy/pkg/logger"
	"github.com/dddpaul/http-over-socks-proxy/pkg/transport"
	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
)

type Proxy struct {
	httpProxy *httputil.ReverseProxy
	port      string
	transport http.RoundTripper
	trace     bool
}

type ProxyOption func(p *Proxy)

func WithPort(port string) ProxyOption {
	return func(p *Proxy) {
		p.port = port
	}
}

func WithSocks(socks string) ProxyOption {
	return func(p *Proxy) {
		p.transport = transport.NewSocksTransport(socks)
	}
}

func WithTrace(enabled bool) ProxyOption {
	return func(p *Proxy) {
		p.trace = enabled
	}
}

func New(opts ...ProxyOption) *Proxy {
	p := &Proxy{}

	for _, opt := range opts {
		opt(p)
	}

	director := func(req *http.Request) {
		ctx := context.WithValue(req.Context(), "trace_id", uuid.New())
		logger.Log(ctx, nil).WithFields(log.Fields{
			"request":    req.RequestURI,
			"method":     req.Method,
			"remote":     req.RemoteAddr,
			"user-agent": req.UserAgent(),
			"referer":    req.Referer(),
		}).Debugf("request")
		if p.trace {
			r := req.WithContext(httptrace.WithClientTrace(ctx, transport.NewTrace(ctx)))
			*req = *r
		}
	}

	modifier := func(res *http.Response) error {
		req := res.Request
		ctx := req.Context()
		logger.Log(ctx, nil).WithFields(log.Fields{
			"status":         res.Status,
			"content-length": res.ContentLength,
		}).Debugf("response")
		return nil
	}

	p.httpProxy = &httputil.ReverseProxy{
		Transport:      p.transport,
		Director:       director,
		ModifyResponse: modifier,
	}

	return p
}

func (p *Proxy) Start() {
	log.Infof("Start HTTP proxy on port %s", p.port)
	if err := http.ListenAndServe(p.port, p); err != nil {
		panic(err)
	}
}

func (p *Proxy) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodConnect {
		proxyConnect(w, req)
	} else {
		p.httpProxy.ServeHTTP(w, req)
	}
}

func proxyConnect(w http.ResponseWriter, req *http.Request) {
	ctx := context.WithValue(req.Context(), "trace_id", uuid.New())
	logger.Log(ctx, nil).WithFields(log.Fields{
		"request":    req.RequestURI,
		"method":     req.Method,
		"remote":     req.RemoteAddr,
		"user-agent": req.UserAgent(),
		"referer":    req.Referer(),
	}).Debugf("request")

	targetConn, err := net.Dial("tcp", req.Host)
	if err != nil {
		logger.Log(ctx, nil).Errorf("request")
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusOK)
	hj, ok := w.(http.Hijacker)
	if !ok {
		panic("HTTP server doesn't support hijacking connection")
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		panic("HTTP hijacking failed")
	}
	logger.Log(ctx, nil).Debugf("TCP tunnel established")

	go tunnelConn(targetConn, clientConn)
	go tunnelConn(clientConn, targetConn)
}

func tunnelConn(dst io.WriteCloser, src io.ReadCloser) {
	io.Copy(dst, src)
	dst.Close()
	src.Close()
}
