package logger

import (
	"context"
	"net/http"

	log "github.com/sirupsen/logrus"
)

func Log(ctx context.Context, err error) *log.Entry {
	entry := log.WithContext(ctx)
	if err != nil {
		entry = entry.WithField("error", err)
	}
	if traceID := ctx.Value("trace_id"); traceID != nil {
		entry = entry.WithField("trace_id", traceID)
	}
	return entry
}

func LogRequest(ctx context.Context, req *http.Request) {
	Log(ctx, nil).WithFields(log.Fields{
		"request":    req.RequestURI,
		"method":     req.Method,
		"remote":     req.RemoteAddr,
		"user-agent": req.UserAgent(),
		"referer":    req.Referer(),
	}).Debugf("request")
}

func LogResponse(ctx context.Context, res *http.Response) {
	Log(ctx, nil).WithFields(log.Fields{
		"status":         res.Status,
		"content-length": res.ContentLength,
	}).Debugf("response")
}
