package proxy

import (
	"io"
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
	if err := http.ListenAndServe(p.port, logger.NewMiddleware(p)); err != nil {
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

	w.WriteHeader(http.StatusOK)
	hj, ok := w.(http.Hijacker)
	if !ok {
		panic("HTTP server doesn't support hijacking connection")
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		panic("HTTP hijacking failed")
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
