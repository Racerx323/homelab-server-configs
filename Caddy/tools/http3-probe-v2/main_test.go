package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"net"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/quic-go/quic-go"
)

func TestRejectsInvalidArgumentsBeforeNetwork(t *testing.T) {
	tests := [][]string{
		{},
		{"-hostname", "proxy.local.theama.co", "-ip", "not-an-ip"},
		{"-hostname", "proxy.local.theama.co", "-ip", "10.1.0.56", "-path", "relative"},
		{"-hostname", "proxy.local.theama.co", "-ip", "10.1.0.56", "-timeout", "0s"},
	}
	for _, args := range tests {
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		if status := run(args, &stdout, &stderr); status != 2 {
			t.Fatalf("run(%q) status = %d, want 2", args, status)
		}
		if stdout.Len() != 0 || stderr.Len() == 0 {
			t.Fatalf("run(%q) produced stdout=%q stderr=%q", args, stdout.String(), stderr.String())
		}
	}
}

func TestHistoricalZeroValueTransportPanics(t *testing.T) {
	if os.Getenv("CADDY_HTTP3_ZERO_TRANSPORT_HELPER") == "1" {
		var transport quic.Transport
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()
		_, _ = transport.DialEarly(ctx, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 9},
			&tls.Config{InsecureSkipVerify: true}, &quic.Config{}) //nolint:gosec
		return
	}
	command := exec.Command(os.Args[0], "-test.run=^TestHistoricalZeroValueTransportPanics$")
	command.Env = append(os.Environ(), "CADDY_HTTP3_ZERO_TRANSPORT_HELPER=1")
	output, err := command.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "panic: runtime error: invalid memory address") {
		t.Fatalf("zero-value transport did not reproduce the historical panic: err=%v output=%q", err, output)
	}
}

func TestCorrectedTransportInitializesAndClosesPacketConn(t *testing.T) {
	resources, err := openQUICResources(net.IPv4(127, 0, 0, 1))
	if err != nil {
		t.Fatal(err)
	}
	if resources.quicTransport.Conn == nil || resources.quicTransport.Conn.LocalAddr() == nil {
		t.Fatal("corrected transport has no usable packet connection")
	}
	if err := resources.close(); err != nil {
		t.Fatal(err)
	}
	if _, err := resources.packetConn.WriteToUDP([]byte("closed"), &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 9}); err == nil {
		t.Fatal("packet connection remained writable after cleanup")
	}
}
