package store

import (
	"path/filepath"
	"testing"

	"radioko-leka/internal/radio"
)

func TestHistoryPersistsDeduplicatesAndLimits(t *testing.T) {
	path := filepath.Join(t.TempDir(), "recent.json")
	history, err := OpenHistory(path, 2)
	if err != nil {
		t.Fatal(err)
	}
	first := radio.Station{ID: "1", Name: "Radio One", URL: "https://example.com/1"}
	second := radio.Station{ID: "2", Name: "Radio Two", URL: "https://example.com/2"}
	third := radio.Station{ID: "3", Name: "Radio Three", URL: "https://example.com/3"}
	for _, station := range []radio.Station{first, second, first, third} {
		if err := history.Add(station); err != nil {
			t.Fatal(err)
		}
	}
	reloaded, err := OpenHistory(path, 2)
	if err != nil {
		t.Fatal(err)
	}
	got := reloaded.List()
	if len(got) != 2 || got[0].ID != third.ID || got[1].ID != first.ID {
		t.Fatalf("unexpected history: %#v", got)
	}
}

func TestSettingsPersistAndClampVolume(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	settings, err := OpenSettings(path)
	if err != nil {
		t.Fatal(err)
	}
	if settings.Data().Volume != 70 || settings.Data().RecentLimit != 30 {
		t.Fatalf("unexpected defaults: %#v", settings.Data())
	}
	if err := settings.SetVolume(135); err != nil {
		t.Fatal(err)
	}
	reloaded, err := OpenSettings(path)
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.Data().Volume != 100 {
		t.Fatalf("volume = %d, want 100", reloaded.Data().Volume)
	}
}
