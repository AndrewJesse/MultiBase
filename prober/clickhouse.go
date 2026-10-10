package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sync"
	"time"
)

type chRow struct {
	TS        string  `json:"ts"`
	Site      string  `json:"site"`
	Probe     string  `json:"probe"`
	Target    string  `json:"target"`
	OK        uint8   `json:"ok"`
	LatencyMS float64 `json:"latency_ms"`
	Value     float64 `json:"value"`
	Error     string  `json:"error"`
}

func toRow(r Result) chRow {
	var ok uint8
	if r.OK {
		ok = 1
	}
	return chRow{
		TS: r.TS.UTC().Format("2006-01-02 15:04:05.000"), Site: r.Site, Probe: r.Probe,
		Target: r.Target, OK: ok, LatencyMS: r.LatencyMS, Value: r.Value, Error: r.Err,
	}
}

// Writer buffers results and inserts them over ClickHouse's HTTP interface.
type Writer struct {
	baseURL string
	client  *http.Client
	mu      sync.Mutex
	buf     []Result
	maxBuf  int
}

func NewWriter(baseURL string, client *http.Client) *Writer {
	return &Writer{baseURL: baseURL, client: client, maxBuf: 1000}
}

func (w *Writer) Add(r Result) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.buf) >= w.maxBuf { // drop oldest rather than grow without bound while ClickHouse is down
		w.buf = w.buf[1:]
	}
	w.buf = append(w.buf, r)
}

func (w *Writer) Flush(ctx context.Context) error {
	w.mu.Lock()
	batch := w.buf
	w.buf = nil
	w.mu.Unlock()
	if len(batch) == 0 {
		return nil
	}
	var body bytes.Buffer
	enc := json.NewEncoder(&body)
	for _, r := range batch {
		if err := enc.Encode(toRow(r)); err != nil {
			return err
		}
	}
	q := url.QueryEscape("INSERT INTO multibase.probe_results (ts,site,probe,target,ok,latency_ms,value,error) FORMAT JSONEachRow")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.baseURL+"/?query="+q, &body)
	if err != nil {
		return err
	}
	resp, err := w.client.Do(req)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode/100 != 2 {
			err = fmt.Errorf("clickhouse status %d", resp.StatusCode)
		}
	}
	if err != nil { // put the batch back so the next flush retries it
		w.mu.Lock()
		w.buf = append(batch, w.buf...)
		w.mu.Unlock()
	}
	return err
}

func (w *Writer) Run(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			fctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = w.Flush(fctx)
			cancel()
			return
		case <-t.C:
			_ = w.Flush(ctx)
		}
	}
}
