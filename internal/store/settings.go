package store

import (
	"encoding/json"
	"fmt"
	"os"
)

type SettingsData struct {
	Volume      int `json:"volume"`
	RecentLimit int `json:"recent_limit"`
}

type Settings struct {
	path string
	data SettingsData
}

func OpenSettings(path string) (*Settings, error) {
	if path == "" {
		var err error
		path, err = configPath("settings.json")
		if err != nil {
			return nil, err
		}
	}
	settings := &Settings{path: path, data: SettingsData{Volume: 70, RecentLimit: 30}}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return settings, nil
	}
	if err != nil {
		return nil, fmt.Errorf("lecture des réglages: %w", err)
	}
	if err := json.Unmarshal(data, &settings.data); err != nil {
		return nil, fmt.Errorf("décodage des réglages: %w", err)
	}
	settings.data.Volume = clampSetting(settings.data.Volume, 0, 100)
	if settings.data.RecentLimit < 1 || settings.data.RecentLimit > 100 {
		settings.data.RecentLimit = 30
	}
	return settings, nil
}

func (s *Settings) Data() SettingsData { return s.data }

func (s *Settings) SetVolume(volume int) error {
	volume = clampSetting(volume, 0, 100)
	if volume == s.data.Volume {
		return nil
	}
	s.data.Volume = volume
	return writeJSON(s.path, "settings-*.json", s.data)
}

func clampSetting(value, min, max int) int {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}
