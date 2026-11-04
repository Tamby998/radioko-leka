package store

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func configPath(filename string) (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("dossier de configuration: %w", err)
	}
	return filepath.Join(configDir, "radioko-leka", filename), nil
}

func writeJSON(path, pattern string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return fmt.Errorf("création du dossier de configuration: %w", err)
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encodage JSON: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), pattern)
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
		return fmt.Errorf("écriture JSON: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryName, path); err != nil {
		return fmt.Errorf("sauvegarde JSON: %w", err)
	}
	return nil
}
