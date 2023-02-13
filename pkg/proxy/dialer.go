package proxy

import (
	"net"
	"net/url"

	log "github.com/sirupsen/logrus"
	"golang.org/x/net/proxy"
)

func NewDialer(socks string) proxy.Dialer {
	if len(socks) == 0 {
		log.Infof("SOCKS5 proxy URL is empty, use DIRECT connection")
		return &net.Dialer{}
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

	d, err := proxy.SOCKS5("tcp", u.Host, auth, proxy.Direct)
	if err != nil {
		log.Infof("SOCKS5 proxy init error, use DIRECT connection")
		return &net.Dialer{}
	}
	return d
}
