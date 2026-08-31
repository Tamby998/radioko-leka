package store

import (
	"encoding/json"
	"fmt"
	"os"

	"radioko-leka/internal/radio"
)

type History struct {
	path     string
	limit    int
	stations []radio.Station
}

func OpenHistory(path string, limit int) (*History, error) {
	if limit < 1 {
		limit = 30
	}
	if path == "" {
		var err error
		path, err = configPath("recent.json")
		if err != nil {
			return nil, err
		}
	}
	history := &History{path: path, limit: limit}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return history, nil
	}
	if err != nil {
		return nil, fmt.Errorf("lecture de l'historique: %w", err)
	}
	if err := json.Unmarshal(data, &history.stations); err != nil {
		return nil, fmt.Errorf("décodage de l'historique: %w", err)
	}
	if len(history.stations) > limit {
		history.stations = history.stations[:limit]
	}
	return history, nil
}

func (h *History) List() []radio.Station {
	return append([]radio.Station(nil), h.stations...)
}

func (h *History) Add(station radio.Station) error {
	key := stationKey(station)
	updated := []radio.Station{station}
	for _, recent := range h.stations {
		if stationKey(recent) != key {
			updated = append(updated, recent)
		}
	}
	if len(updated) > h.limit {
		updated = updated[:h.limit]
	}
	h.stations = updated
	return writeJSON(h.path, "recent-*.json", h.stations)
}
