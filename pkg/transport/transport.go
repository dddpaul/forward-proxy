package transport

import (
	"net/http"
	"net/http/httptrace"
	"net/url"
	"time"

	log "github.com/sirupsen/logrus"
	"golang.org/x/net/proxy"
)

func NewSocksTransport(socks string) http.RoundTripper {
	if len(socks) == 0 {
		return http.DefaultTransport
	}

	u, err := url.Parse(socks)
	if err != nil {
		panic(err)
	}

	var auth *proxy.Auth
	if u.User != nil {
		auth = &proxy.Auth{
			User: u.User.Username(),
		}
		if p, ok := u.User.Password(); ok {
			auth.Password = p
		}
	}

	dialer, err := proxy.SOCKS5("tcp", u.Host, auth, proxy.Direct)
	if err != nil {
		panic(err)
	}
	return &http.Transport{
		Dial: dialer.Dial,
	}
}

func NewTrace() *httptrace.ClientTrace {
	var start time.Time
	return &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			log.WithField("time_to_first_byte_received", time.Since(start)).Tracef("trace")
		},
	}
}
