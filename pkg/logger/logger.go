package logger

import (
	"context"

	log "github.com/sirupsen/logrus"
)

func Log(ctx context.Context, err error) *log.Entry {
	entry := log.WithContext(ctx)
	if err != nil {
		entry = entry.WithField("error", err)
	}
	return entry
}
