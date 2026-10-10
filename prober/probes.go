package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// Result is one probe execution, stored as a row in ClickHouse.
type Result struct {
	TS        time.Time
	Site      string
	Probe     string
	Target    string
	OK        bool
	LatencyMS float64
	Value     float64
	Err       string
}

type Probe interface {
	Name() string
	Run(ctx context.Context) Result
}

type DialFunc = func(ctx context.Context, network, addr string) (net.Conn, error)

type queryProbe struct {
	site, dsn string
	dial      DialFunc
}

func (p queryProbe) Name() string { return "query" }

func (p queryProbe) Run(ctx context.Context) Result {
	r := Result{TS: time.Now().UTC(), Site: p.site, Probe: p.Name(), Target: "primary"}
	start := time.Now()
	var one int
	err := withConn(ctx, p.dsn, p.dial, func(c *pgx.Conn) error {
		return c.QueryRow(ctx, "SELECT 1").Scan(&one)
	})
	return finish(r, start, err, 0)
}

type lagProbe struct {
	site, dsn string
	dial      DialFunc
}

func (p lagProbe) Name() string { return "replication_lag" }

func (p lagProbe) Run(ctx context.Context) Result {
	r := Result{TS: time.Now().UTC(), Site: p.site, Probe: p.Name(), Target: "replica"}
	start := time.Now()
	var lag float64
	err := withConn(ctx, p.dsn, p.dial, func(c *pgx.Conn) error {
		return c.QueryRow(ctx,
			"SELECT COALESCE(EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()), 0)::float8").Scan(&lag)
	})
	return finish(r, start, err, lag)
}

type authProbe struct {
	site, url string
	client    *http.Client
}

func (p authProbe) Name() string { return "auth" }

func (p authProbe) Run(ctx context.Context) Result {
	r := Result{TS: time.Now().UTC(), Site: p.site, Probe: p.Name(), Target: p.url}
	start := time.Now()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.url, nil)
	if err == nil {
		var resp *http.Response
		resp, err = p.client.Do(req)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode != http.StatusOK {
				err = fmt.Errorf("status %d", resp.StatusCode)
			}
		}
	}
	return finish(r, start, err, 0)
}

func withConn(ctx context.Context, dsn string, dial DialFunc, fn func(*pgx.Conn) error) error {
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return err
	}
	if dial != nil {
		cfg.DialFunc = dial
	}
	c, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		return err
	}
	defer c.Close(context.Background())
	return fn(c)
}

func finish(r Result, start time.Time, err error, value float64) Result {
	r.LatencyMS = float64(time.Since(start).Microseconds()) / 1000
	r.Value = value
	r.OK = err == nil
	if err != nil {
		r.Err = err.Error()
	}
	return r
}
