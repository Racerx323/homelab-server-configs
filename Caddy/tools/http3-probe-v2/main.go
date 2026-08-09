package main

import (
	"context"
	"crypto/tls"
	"errors"
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

type quicResources struct {
	packetConn    *net.UDPConn
	quicTransport *quic.Transport
}

func openQUICResources(ip net.IP) (*quicResources, error) {
	network := "udp6"
	localIP := net.IPv6unspecified
	if ip.To4() != nil {
		network = "udp4"
		localIP = net.IPv4zero
	}
	packetConn, err := net.ListenUDP(network, &net.UDPAddr{IP: localIP})
	if err != nil {
		return nil, fmt.Errorf("open %s packet connection: %w", network, err)
	}
	return &quicResources{
		packetConn:    packetConn,
		quicTransport: &quic.Transport{Conn: packetConn},
	}, nil
}

func (resources *quicResources) close() error {
	return errors.Join(resources.quicTransport.Close(), resources.packetConn.Close())
}

func run(args []string, stdout, stderr io.Writer) (status int) {
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
	parsedIP := net.ParseIP(*ipAddress)
	if *hostname == "" || parsedIP == nil || *path == "" || (*path)[0] != '/' || *timeout <= 0 {
		fmt.Fprintln(stderr, "hostname, literal IP, absolute path, and positive timeout are required")
		return 2
	}

	resources, err := openQUICResources(parsedIP)
	if err != nil {
		fmt.Fprintf(stderr, "QUIC transport initialization failed: %v\n", err)
		return 1
	}
	defer func() {
		if closeErr := resources.close(); closeErr != nil && status == 0 {
			fmt.Fprintf(stderr, "QUIC transport cleanup failed: %v\n", closeErr)
			status = 1
		}
	}()

	target := net.JoinHostPort(*ipAddress, "443")
	requestURL := (&url.URL{Scheme: "https", Host: *hostname, Path: *path}).String()
	tlsConfig := &tls.Config{
		MinVersion:         tls.VersionTLS12,
		ServerName:         *hostname,
		InsecureSkipVerify: *insecure, // Protocol isolation only; trust is Action 27.
		NextProtos:         []string{http3.NextProtoH3},
	}
	transport := &http3.Transport{
		TLSClientConfig: tlsConfig,
		QUICConfig: &quic.Config{
			HandshakeIdleTimeout: 3 * time.Second,
			MaxIdleTimeout:       *timeout,
		},
		Dial: func(ctx context.Context, _ string, tlsConf *tls.Config, quicConf *quic.Config) (*quic.Conn, error) {
			udpAddress, resolveErr := net.ResolveUDPAddr("udp", target)
			if resolveErr != nil {
				return nil, resolveErr
			}
			return resources.quicTransport.DialEarly(ctx, udpAddress, tlsConf, quicConf)
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
