package proxy

import (
	"io"
	"net"
	"net/http"
	"net/http/httputil"

	"github.com/dddpaul/http-over-socks-proxy/pkg/logger"
	"github.com/dddpaul/http-over-socks-proxy/pkg/trace"
	log "github.com/sirupsen/logrus"
)

type Proxy struct {
	httpProxy, httpsProxy http.Handler
	port                  string
	trace                 bool
}

type ProxyOption func(p *Proxy)

func WithPort(port string) ProxyOption {
	return func(p *Proxy) {
		p.port = port
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
		Director: func(req *http.Request) {
			ctx := trace.Context(req)
			logger.LogRequest(ctx, req)
			if p.trace {
				trace.Request(ctx, req)
			}
		},
		ModifyResponse: func(res *http.Response) error {
			logger.LogResponse(res.Request.Context(), res)
			return nil
		},
	}

	p.httpsProxy = &HttpsProxy{
		trace: p.trace,
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
		p.httpsProxy.ServeHTTP(w, req)
	} else {
		p.httpProxy.ServeHTTP(w, req)
	}
}

type HttpsProxy struct {
	trace bool
}

func (p *HttpsProxy) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	ctx := trace.Context(req)
	logger.LogRequest(ctx, req)
	if p.trace {
		trace.Request(ctx, req)
	}

	var d net.Dialer
	targetConn, err := d.DialContext(ctx, "tcp", req.Host)
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
	logger.Log(ctx, nil).Tracef("TCP tunnel established")

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
