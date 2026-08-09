package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
)

func run(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("caddy-http3-probe", flag.ContinueOnError)
	flags.SetOutput(stderr)
	hostname := flags.String("hostname", "", "TLS server name and HTTP host")
	ipAddress := flags.String("ip", "", "literal destination IP address")
	path := flags.String("path", "/", "request path")
	timeout := flags.Duration("timeout", 8*time.Second, "overall request timeout")
	insecure := flags.Bool("insecure", false, "skip certificate verification")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *hostname == "" || net.ParseIP(*ipAddress) == nil || *path == "" || (*path)[0] != '/' || *timeout <= 0 {
		fmt.Fprintln(stderr, "hostname, literal IP, absolute path, and positive timeout are required")
		return 2
	}

	target := net.JoinHostPort(*ipAddress, "443")
	requestURL := (&url.URL{Scheme: "https", Host: *hostname, Path: *path}).String()
	tlsConfig := &tls.Config{
		MinVersion:         tls.VersionTLS12,
		ServerName:         *hostname,
		InsecureSkipVerify: *insecure, // Protocol isolation only; trust is Action 27.
		NextProtos:         []string{http3.NextProtoH3},
	}
	quicTransport := &quic.Transport{}
	transport := &http3.Transport{
		TLSClientConfig: tlsConfig,
		QUICConfig: &quic.Config{
			HandshakeIdleTimeout: 3 * time.Second,
			MaxIdleTimeout:       *timeout,
		},
		Dial: func(ctx context.Context, _ string, tlsConf *tls.Config, quicConf *quic.Config) (*quic.Conn, error) {
			udpAddress, err := net.ResolveUDPAddr("udp", target)
			if err != nil {
				return nil, err
			}
			return quicTransport.DialEarly(ctx, udpAddress, tlsConf, quicConf)
		},
	}
	defer transport.Close()
	client := &http.Client{
		Transport: transport,
		Timeout:   *timeout,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	request, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		fmt.Fprintf(stderr, "request creation failed: %v\n", err)
		return 1
	}
	response, err := client.Do(request)
	if err != nil {
		fmt.Fprintf(stderr, "HTTP/3 request failed: %v\n", err)
		return 1
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1025))
	if err != nil {
		fmt.Fprintf(stderr, "response read failed: %v\n", err)
		return 1
	}
	if len(body) > 1024 {
		fmt.Fprintln(stderr, "response body exceeded 1024 bytes")
		return 1
	}

	fmt.Fprintf(stdout, "protocol=%s\n", response.Proto)
	fmt.Fprintf(stdout, "status=%d\n", response.StatusCode)
	fmt.Fprintf(stdout, "remote_ip=%s\n", *ipAddress)
	fmt.Fprintf(stdout, "body_bytes=%d\n", len(body))
	fmt.Fprintln(stdout, "redirects=0")
	return 0
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
