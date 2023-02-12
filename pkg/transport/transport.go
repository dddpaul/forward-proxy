package transport

import (
	"context"
	"net/http"
	"net/http/httptrace"
	"net/url"
	"time"

	"github.com/dddpaul/http-over-socks-proxy/pkg/logger"
)

func NewSocksTransport(socks string) http.RoundTripper {
	if len(socks) == 0 {
		return http.DefaultTransport
	}

	u, err := url.Parse(socks)
	if err != nil {
		panic(err)
	}

	proxies := func(req *http.Request) (*url.URL, error) {
		return u, nil
	}

	t := http.DefaultTransport

	if transport, ok := t.(*http.Transport); ok {
		transport.Proxy = proxies
		return transport
	}

	return nil
}

func NewTrace(ctx context.Context) *httptrace.ClientTrace {
	var start time.Time
	return &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			logger.Log(ctx, nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
}
