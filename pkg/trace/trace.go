package trace

import (
	"context"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/dddpaul/forward-proxy/pkg/logger"
	"github.com/google/uuid"
)

type Trace struct {
	Handler http.Handler
}

func (t *Trace) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	withTraceID(req)
	logger.LogRequest(req)
	t.Handler.ServeHTTP(w, req)
}

// Inject trace_id field into request's context and modify original request
func withTraceID(req *http.Request) {
	ctx := context.WithValue(req.Context(), "trace_id", uuid.New())
	r := req.WithContext(ctx)
	*req = *r
}

// Inject ClientTrace into request's context and modify original request
func WithClientTrace(req *http.Request) {
	var start time.Time
	trace := &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			logger.Log(req.Context(), nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
	r := req.WithContext(httptrace.WithClientTrace(req.Context(), trace))
	*req = *r
}
