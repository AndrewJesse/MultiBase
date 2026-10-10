package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"tailscale.com/tsnet"
)

var (
	probeTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "multibase_probe_total", Help: "Probe executions by result."}, []string{"probe", "site", "result"})
	probeLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "multibase_probe_latency_seconds", Help: "Probe latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5}}, []string{"probe", "site"})
	replLag = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "multibase_replication_lag_seconds", Help: "Replica replay lag."}, []string{"site"})
)

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	prometheus.MustRegister(probeTotal, probeLatency, replLag)

	site := env("SITE", "unknown")
	interval, err := time.ParseDuration(env("PROBE_INTERVAL", "15s"))
	if err != nil {
		log.Fatal(err)
	}

	// With TS_AUTHKEY the prober is its own tailnet node, so probes originate from this site's network path.
	var dial DialFunc
	client := http.DefaultClient
	if key := os.Getenv("TS_AUTHKEY"); key != "" {
		srv := &tsnet.Server{
			Hostname:  "mb-prober-" + site,
			AuthKey:   key,
			Ephemeral: true,
			Dir:       env("TS_STATE_DIR", "/tmp/tsnet"),
		}
		defer srv.Close()
		dial = srv.Dial
		client = srv.HTTPClient()
	}

	probes := []Probe{}
	if dsn := os.Getenv("PG_PRIMARY_DSN"); dsn != "" {
		probes = append(probes, queryProbe{site: site, dsn: dsn, dial: dial})
	}
	if dsn := os.Getenv("PG_REPLICA_DSN"); dsn != "" {
		probes = append(probes, lagProbe{site: site, dsn: dsn, dial: dial})
	}
	if u := os.Getenv("AUTH_URL"); u != "" {
		probes = append(probes, authProbe{site: site, url: u, client: client})
	}
	if len(probes) == 0 {
		log.Fatal("no probes configured (PG_PRIMARY_DSN, PG_REPLICA_DSN, AUTH_URL)")
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var w *Writer
	if ch := os.Getenv("CLICKHOUSE_URL"); ch != "" {
		w = NewWriter(ch, http.DefaultClient)
		go w.Run(ctx, 10*time.Second)
	}

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/healthz", func(rw http.ResponseWriter, _ *http.Request) { rw.WriteHeader(http.StatusOK) })
		log.Fatal(http.ListenAndServe(env("METRICS_ADDR", ":9100"), mux))
	}()

	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		for _, p := range probes {
			go func(p Probe) {
				pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
				defer cancel()
				r := p.Run(pctx)
				record(r)
				if w != nil {
					w.Add(r)
				}
			}(p)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func record(r Result) {
	result := "ok"
	if !r.OK {
		result = "fail"
		log.Printf("probe %s failed: %s", r.Probe, r.Err)
	}
	probeTotal.WithLabelValues(r.Probe, r.Site, result).Inc()
	probeLatency.WithLabelValues(r.Probe, r.Site).Observe(r.LatencyMS / 1000)
	if r.Probe == "replication_lag" && r.OK {
		replLag.WithLabelValues(r.Site).Set(r.Value)
	}
}
