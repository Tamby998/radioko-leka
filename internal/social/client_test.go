package social

import (
	"testing"

	atradio "github.com/tsirysndr/atradio.fm/sdk/go"

	"radioko-leka/internal/radio"
)

func TestStationMappingAndCompatibleFavoriteKey(t *testing.T) {
	station := radio.Station{ID: "rb:malagasy", Name: "Radio Malagasy", URL: "https://example.com/live", Country: "Madagascar", Codec: "MP3"}
	wire := toStationInfo(station)
	if wire.StationID != station.ID || wire.StreamURL != station.URL || wire.Source != "radio-browser" {
		t.Fatalf("unexpected wire station: %#v", wire)
	}
	if got := atradio.FavoriteRkey(wire.StationID); got != "b430668b21a521dc" {
		t.Fatalf("favorite rkey = %q", got)
	}
	if restored := fromStationInfo(wire); restored.ID != station.ID || restored.URL != station.URL {
		t.Fatalf("unexpected restored station: %#v", restored)
	}
}
