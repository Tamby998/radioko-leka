package tui

import (
	"path/filepath"
	"testing"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
	"radioko-leka/internal/store"
)

func TestSearchResultOpensStationList(t *testing.T) {
	favorites, err := store.OpenFavorites(filepath.Join(t.TempDir(), "favorites.json"))
	if err != nil {
		t.Fatal(err)
	}
	history, err := store.OpenHistory(filepath.Join(t.TempDir(), "recent.json"), 30)
	if err != nil {
		t.Fatal(err)
	}
	settings, err := store.OpenSettings(filepath.Join(t.TempDir(), "settings.json"))
	if err != nil {
		t.Fatal(err)
	}
	model := New(radio.NewClient(), player.New(), favorites, history, settings)
	station := radio.Station{ID: "mg-1", Name: "Radio Malagasy", URL: "https://example.com/radio"}
	updated, _ := model.Update(stationResult{
		stations: []radio.Station{station},
		title:    "Résultats · Malagasy",
		screen:   screenResults,
	})
	result := updated.(Model)
	if result.screen != screenResults || len(result.stations) != 1 {
		t.Fatalf("result screen = %v with %d stations", result.screen, len(result.stations))
	}
}
