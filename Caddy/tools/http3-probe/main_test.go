package main

import (
	"bytes"
	"testing"
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
