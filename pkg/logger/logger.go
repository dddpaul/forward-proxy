package logger

import (
	"context"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
)

const TRACE_ID = "trace_id"

type LoggingMiddleware struct {
	handler http.Handler
}

func (l *LoggingMiddleware) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	withTraceID(req)
	LogRequest(req)
	l.handler.ServeHTTP(w, req)
}

func NewMiddleware(h http.Handler) http.Handler {
	return &LoggingMiddleware{handler: h}
}

// Inject trace_id field into request's context and modify original request
func withTraceID(req *http.Request) {
	ctx := context.WithValue(req.Context(), TRACE_ID, uuid.New())
	r := req.WithContext(ctx)
	*req = *r
}

// Inject ClientTrace into request's context and modify original request
func WithClientTrace(req *http.Request) {
	var start time.Time
	trace := &httptrace.ClientTrace{
		GetConn: func(hostPort string) { start = time.Now() },
		GotFirstResponseByte: func() {
			Log(req.Context(), nil).WithField("time_to_first_byte_received", time.Since(start)).Tracef("request")
		},
	}
	r := req.WithContext(httptrace.WithClientTrace(req.Context(), trace))
	*req = *r
}

func Log(ctx context.Context, err error) *log.Entry {
	entry := log.WithContext(ctx)
	if err != nil {
		entry = entry.WithField("error", err)
	}
	if traceID := ctx.Value(TRACE_ID); traceID != nil {
		entry = entry.WithField(TRACE_ID, traceID)
	}
	return entry
}

func LogRequest(req *http.Request) {
	Log(req.Context(), nil).WithFields(log.Fields{
		"request":    req.RequestURI,
		"method":     req.Method,
		"remote":     req.RemoteAddr,
		"user-agent": req.UserAgent(),
		"referer":    req.Referer(),
	}).Debugf("request")
}

func LogResponse(res *http.Response) {
	Log(res.Request.Context(), nil).WithFields(log.Fields{
		"status":         res.Status,
		"content-length": res.ContentLength,
	}).Debugf("response")
}
