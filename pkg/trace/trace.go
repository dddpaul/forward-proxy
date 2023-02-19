package trace

import (
	"context"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/dddpaul/forward-proxy/pkg/logger"
	"github.com/google/uuid"
)

func New(ctx context.Context) *httptrace.ClientTrace {
	var start time.Time
	return &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			logger.Log(ctx, nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
}

func Context(req *http.Request) context.Context {
	return context.WithValue(req.Context(), "trace_id", uuid.New())
}

func Request(ctx context.Context, req *http.Request) {
	r := req.WithContext(httptrace.WithClientTrace(ctx, New(ctx)))
	*req = *r
}
