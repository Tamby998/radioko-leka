package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
	"radioko-leka/internal/tui"
)

func main() {
	audio := player.New()
	program := tea.NewProgram(tui.New(radio.NewClient(), audio), tea.WithAltScreen())
	if _, err := program.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
}
