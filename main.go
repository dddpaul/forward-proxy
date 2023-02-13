package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/dddpaul/http-over-socks-proxy/pkg/proxy"
	log "github.com/sirupsen/logrus"
)

var (
	verbose, trace bool
	socks          string
	port           string
)

func main() {
	flag.BoolVar(&verbose, "verbose", false, "Enable debug logging")
	flag.BoolVar(&trace, "trace", false, "Enable network tracing")
	flag.StringVar(&port, "port", ":8080", "Port to listen (prepended by colon), i.e. :8080")
	flag.StringVar(&socks, "socks", LookupEnvOrString("SOCKS_URL", ""), "SOCKS5 proxy URL, i.e. socks://127.0.0.1:1080")

	log.SetFormatter(&log.TextFormatter{
		DisableColors: true,
		FullTimestamp: true,
	})

	flag.Parse()
	log.Printf("Configuration %v", getConfig(flag.CommandLine))

	if verbose {
		log.SetLevel(log.DebugLevel)
	}

	if trace {
		log.SetLevel(log.TraceLevel)
	}

	p := proxy.New(
		proxy.WithPort(port),
		proxy.WithSocks(socks),
		proxy.WithTrace(trace))

	p.Start()
}

func LookupEnvOrString(key string, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return defaultVal
}

func getConfig(fs *flag.FlagSet) []string {
	cfg := make([]string, 0, 10)
	fs.VisitAll(func(f *flag.Flag) {
		cfg = append(cfg, fmt.Sprintf("%s:%q", f.Name, f.Value.String()))
	})
	return cfg
}
