package store

import (
	"encoding/json"
	"fmt"
	"os"

	"radioko-leka/internal/radio"
)

type Favorites struct {
	path     string
	stations []radio.Station
}

func OpenFavorites(path string) (*Favorites, error) {
	if path == "" {
		var err error
		path, err = configPath("favorites.json")
		if err != nil {
			return nil, err
		}
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

func (f *Favorites) Ensure(station radio.Station) (bool, error) {
	if f.Contains(station) {
		return false, nil
	}
	f.stations = append(f.stations, station)
	return true, f.save()
}

func (f *Favorites) save() error {
	return writeJSON(f.path, "favorites-*.json", f.stations)
}

func stationKey(station radio.Station) string {
	if station.ID != "" {
		return station.ID
	}
	return station.URL
}
