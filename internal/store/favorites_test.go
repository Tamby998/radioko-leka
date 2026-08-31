package store

import (
	"path/filepath"
	"testing"

	"radioko-leka/internal/radio"
)

func TestFavoritesPersist(t *testing.T) {
	path := filepath.Join(t.TempDir(), "favorites.json")
	favorites, err := OpenFavorites(path)
	if err != nil {
		t.Fatal(err)
	}
	station := radio.Station{ID: "malagasy-1", Name: "Radio Malagasy", URL: "https://example.com/radio"}
	added, err := favorites.Toggle(station)
	if err != nil || !added {
		t.Fatalf("Toggle add = %v, %v", added, err)
	}
	reloaded, err := OpenFavorites(path)
	if err != nil {
		t.Fatal(err)
	}
	if !reloaded.Contains(station) || len(reloaded.List()) != 1 {
		t.Fatal("favorite was not persisted")
	}
	added, err = reloaded.Toggle(station)
	if err != nil || added || len(reloaded.List()) != 0 {
		t.Fatalf("Toggle remove = %v, %v", added, err)
	}
}
