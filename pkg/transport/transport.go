package transport

import (
	"context"
	"net/http/httptrace"
	"time"

	"github.com/dddpaul/http-over-socks-proxy/pkg/logger"
)

func NewTrace(ctx context.Context) *httptrace.ClientTrace {
	var start time.Time
	return &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			logger.Log(ctx, nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
}
