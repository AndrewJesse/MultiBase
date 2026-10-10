package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAuthProbe(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ok" {
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	good := authProbe{site: "s", url: srv.URL + "/ok", client: srv.Client()}.Run(context.Background())
	if !good.OK {
		t.Fatalf("expected ok, got %+v", good)
	}
	bad := authProbe{site: "s", url: srv.URL + "/bad", client: srv.Client()}.Run(context.Background())
	if bad.OK || bad.Err == "" {
		t.Fatalf("expected failure, got %+v", bad)
	}
}

func TestWriterFlush(t *testing.T) {
	var got string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		got = string(b)
	}))
	defer srv.Close()

	w := NewWriter(srv.URL, srv.Client())
	w.Add(Result{TS: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC), Site: "x", Probe: "query", OK: true, LatencyMS: 1.5})
	if err := w.Flush(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, `"ts":"2026-01-02 03:04:05.000"`) || !strings.Contains(got, `"ok":1`) {
		t.Fatalf("unexpected body: %s", got)
	}
}

func TestWriterRetainsBatchOnFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	w := NewWriter(srv.URL, srv.Client())
	w.Add(Result{Probe: "query"})
	if err := w.Flush(context.Background()); err == nil {
		t.Fatal("expected error")
	}
	if len(w.buf) != 1 {
		t.Fatalf("batch not retained: %d", len(w.buf))
	}
}
