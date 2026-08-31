package store

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"radioko-leka/internal/radio"
)

type Favorites struct {
	path     string
	stations []radio.Station
}

func OpenFavorites(path string) (*Favorites, error) {
	if path == "" {
		configDir, err := os.UserConfigDir()
		if err != nil {
			return nil, fmt.Errorf("dossier de configuration: %w", err)
		}
		path = filepath.Join(configDir, "radioko-leka", "favorites.json")
	}
	favorites := &Favorites{path: path}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return favorites, nil
	}
	if err != nil {
		return nil, fmt.Errorf("lecture des favoris: %w", err)
	}
	if err := json.Unmarshal(data, &favorites.stations); err != nil {
		return nil, fmt.Errorf("décodage des favoris: %w", err)
	}
	return favorites, nil
}

func (f *Favorites) List() []radio.Station {
	return append([]radio.Station(nil), f.stations...)
}

func (f *Favorites) Contains(station radio.Station) bool {
	key := stationKey(station)
	for _, favorite := range f.stations {
		if stationKey(favorite) == key {
			return true
		}
	}
	return false
}

func (f *Favorites) Toggle(station radio.Station) (bool, error) {
	key := stationKey(station)
	for index, favorite := range f.stations {
		if stationKey(favorite) == key {
			f.stations = append(f.stations[:index], f.stations[index+1:]...)
			return false, f.save()
		}
	}
	f.stations = append(f.stations, station)
	return true, f.save()
}

func (f *Favorites) save() error {
	if err := os.MkdirAll(filepath.Dir(f.path), 0700); err != nil {
		return fmt.Errorf("création du dossier des favoris: %w", err)
	}
	data, err := json.MarshalIndent(f.stations, "", "  ")
	if err != nil {
		return fmt.Errorf("encodage des favoris: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(f.path), "favorites-*.json")
	if err != nil {
		return fmt.Errorf("création du fichier temporaire: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if err := temporary.Chmod(0600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return fmt.Errorf("écriture des favoris: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryName, f.path); err != nil {
		return fmt.Errorf("sauvegarde des favoris: %w", err)
	}
	return nil
}

func stationKey(station radio.Station) string {
	if station.ID != "" {
		return station.ID
	}
	return station.URL
}
