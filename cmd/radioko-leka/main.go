package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
	"radioko-leka/internal/store"
	"radioko-leka/internal/tui"
)

func main() {
	settings, err := store.OpenSettings("")
	if err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
	audio := player.NewWithVolume(settings.Data().Volume)
	favorites, err := store.OpenFavorites("")
	if err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
	history, err := store.OpenHistory("", settings.Data().RecentLimit)
	if err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
	program := tea.NewProgram(tui.New(radio.NewClient(), audio, favorites, history, settings), tea.WithAltScreen())
	if _, err := program.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
}
