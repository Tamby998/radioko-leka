package radio

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestIntegrationMadagascarCatalog(t *testing.T) {
	if os.Getenv("RADIOKO_INTEGRATION") != "1" {
		t.Skip("set RADIOKO_INTEGRATION=1 to run live API tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	stations, err := NewClient().Madagascar(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(stations) == 0 {
		t.Fatal("Radio Browser returned no Malagasy stations")
	}
	for _, station := range stations {
		if station.CountryCode != "MG" {
			t.Fatalf("station %q has country code %q", station.Name, station.CountryCode)
		}
	}
}
