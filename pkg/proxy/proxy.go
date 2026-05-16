package proxy

import (
	"io"
	"net"
	"net/http"
	"net/http/httputil"
	"time"

	"github.com/dddpaul/forward-proxy/pkg/logger"
	log "github.com/sirupsen/logrus"
	"golang.org/x/net/proxy"
)

type Proxy struct {
	httpProxy, httpsProxy http.Handler
	dialer                proxy.Dialer
	port                  string
	trace                 bool
}

type ProxyOption func(p *Proxy)

func WithPort(port string) ProxyOption {
	return func(p *Proxy) {
		p.port = port
	}
}

func WithSocks(socks string) ProxyOption {
	return func(p *Proxy) {
		p.dialer = NewDialer(socks)
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

	p.httpProxy = &httputil.ReverseProxy{
		Transport: &http.Transport{
			Dial: p.dialer.Dial,
		},
		Rewrite: func(r *httputil.ProxyRequest) {
			if p.trace {
				logger.WithClientTrace(r.Out)
			}
		},
		ModifyResponse: func(res *http.Response) error {
			logger.LogResponse(res)
			return nil
		},
	}

	p.httpsProxy = &HttpsProxy{
		dialer: p.dialer,
		trace:  p.trace,
	}

	return p
}

func (p *Proxy) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodConnect {
		p.httpsProxy.ServeHTTP(w, req)
	} else {
		p.httpProxy.ServeHTTP(w, req)
	}
}

func (p *Proxy) Start() {
	log.Infof("Start HTTP proxy on port %s", p.port)

	ln, err := net.Listen("tcp4", p.port)
	if err != nil {
		panic(err)
	}
	if err := http.Serve(ln, logger.NewMiddleware(p)); err != nil {
		panic(err)
	}
}

type HttpsProxy struct {
	dialer proxy.Dialer
	trace  bool
}

func (p *HttpsProxy) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	start := time.Now()
	targetConn, err := p.dialer.Dial("tcp", req.Host)
	if err != nil {
		logger.Log(req.Context(), nil).Errorf("request")
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	hj, ok := w.(http.Hijacker)
	if !ok {
		logger.Log(req.Context(), nil).Error("HTTP server doesn't support hijacking connection")
		targetConn.Close()
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		logger.Log(req.Context(), nil).Errorf("HTTP hijacking failed: %v", err)
		targetConn.Close()
		return
	}

	// Spec-minimal CONNECT response written directly to the raw socket — Go's
	// ResponseWriter would inject Date and Transfer-Encoding: chunked, which
	// strict clients (e.g. bun's fetch) reject for a CONNECT 200.
	if _, err := clientConn.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n")); err != nil {
		logger.Log(req.Context(), nil).Errorf("write CONNECT response failed: %v", err)
		targetConn.Close()
		clientConn.Close()
		return
	}

	logger.Log(req.Context(), nil).WithFields(log.Fields{
		"remote":          clientConn.RemoteAddr(),
		"time_to_connect": time.Since(start),
	}).Tracef("TCP tunnel established")

	copy := func(dst io.WriteCloser, src io.ReadCloser) {
		defer func() {
			dst.Close()
			src.Close()
		}()
		io.Copy(dst, src)
	}

	go copy(targetConn, clientConn)
	go copy(clientConn, targetConn)
}
