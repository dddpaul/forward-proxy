package trace

import (
	"context"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/dddpaul/forward-proxy/pkg/logger"
	"github.com/google/uuid"
)

// Inject trace_id field into request's context
func WithTraceID(req *http.Request) context.Context {
	return context.WithValue(req.Context(), "trace_id", uuid.New())
}

// Inject ClientTrace into request's context and modify original request
func WithClientTrace(ctx context.Context, req *http.Request) {
	var start time.Time
	trace := &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			logger.Log(ctx, nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
	r := req.WithContext(httptrace.WithClientTrace(ctx, trace))
	*req = *r
}
