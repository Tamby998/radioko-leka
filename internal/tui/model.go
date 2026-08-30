package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
)

type searchResult struct {
	stations []radio.Station
	err      error
}

type Model struct {
	client   *radio.Client
	player   *player.Player
	query    string
	stations []radio.Station
	cursor   int
	loading  bool
	message  string
	playing  string
	width    int
}

func New(client *radio.Client, audio *player.Player) Model {
	return Model{client: client, player: audio, message: "Tapez une recherche puis Entrée."}
}

func (m Model) Init() tea.Cmd { return nil }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
	case searchResult:
		m.loading = false
		if msg.err != nil {
			m.message = "Erreur: " + msg.err.Error()
			return m, nil
		}
		m.stations = msg.stations
		m.cursor = 0
		m.message = fmt.Sprintf("%d station(s) trouvée(s).", len(msg.stations))
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			m.player.Stop()
			return m, tea.Quit
		case "q":
			if len(m.stations) > 0 {
				m.player.Stop()
				return m, tea.Quit
			}
			m.query += "q"
		case "up":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down":
			if m.cursor+1 < len(m.stations) {
				m.cursor++
			}
		case "left":
			volume, err := m.player.ChangeVolume(-5)
			if err != nil {
				m.message = "Erreur volume: " + err.Error()
			} else {
				m.message = fmt.Sprintf("Volume: %d%%", volume)
			}
		case "right":
			volume, err := m.player.ChangeVolume(5)
			if err != nil {
				m.message = "Erreur volume: " + err.Error()
			} else {
				m.message = fmt.Sprintf("Volume: %d%%", volume)
			}
		case " ":
			if len(m.stations) == 0 {
				m.query += " "
				break
			}
			paused, err := m.player.TogglePause()
			if err != nil {
				m.message = "Erreur pause: " + err.Error()
			} else if paused {
				m.message = "Lecture en pause."
			} else {
				m.message = "Lecture reprise."
			}
		case "m":
			if len(m.stations) == 0 {
				m.query += "m"
				break
			}
			muted, err := m.player.ToggleMute()
			if err != nil {
				m.message = "Erreur mute: " + err.Error()
			} else if muted {
				m.message = "Son coupé."
			} else {
				m.message = "Son rétabli."
			}
		case "enter":
			if len(m.stations) > 0 {
				station := m.stations[m.cursor]
				if err := m.player.Play(station.URL); err != nil {
					m.message = "Erreur audio: " + err.Error()
				} else {
					m.playing = station.Name
					m.message = "Lecture démarrée."
				}
			} else if strings.TrimSpace(m.query) != "" {
				m.loading = true
				m.message = "Recherche en cours…"
				return m, searchCmd(m.client, m.query)
			}
		case "esc":
			m.player.Stop()
			m.playing = ""
			m.message = "Lecture arrêtée."
		case "backspace":
			if len(m.stations) == 0 && len(m.query) > 0 {
				m.query = m.query[:len(m.query)-1]
			}
		case "/":
			m.stations = nil
			m.query = ""
			m.message = "Nouvelle recherche."
		default:
			if len(m.stations) == 0 && len(msg.Runes) > 0 {
				m.query += string(msg.Runes)
			}
		}
	}
	return m, nil
}

func searchCmd(client *radio.Client, query string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		stations, err := client.Search(ctx, query, 30)
		return searchResult{stations: stations, err: err}
	}
}

func (m Model) View() string {
	var b strings.Builder
	b.WriteString("RADIOKO LEKA — radio dans le terminal\n\n")
	if len(m.stations) == 0 {
		b.WriteString("Recherche : " + m.query + "█\n")
	} else {
		for i, station := range m.stations {
			cursor := "  "
			if i == m.cursor {
				cursor = "> "
			}
			details := strings.Trim(strings.Join([]string{station.Country, station.Codec}, " · "), " ·")
			b.WriteString(fmt.Sprintf("%s%s  [%s]\n", cursor, station.Name, details))
		}
	}
	b.WriteString("\n")
	if m.playing != "" {
		volume, paused, muted := m.player.Status()
		state := "▶"
		if paused {
			state = "⏸"
		}
		sound := fmt.Sprintf("volume %d%%", volume)
		if muted {
			sound = "muet"
		}
		b.WriteString(fmt.Sprintf("%s %s · %s\n", state, m.playing, sound))
	}
	b.WriteString(m.message + "\n")
	b.WriteString("\nEntrée: lire/changer · ↑↓: choisir · ←→: volume · Espace: pause · m: mute\n")
	b.WriteString("/: rechercher · Échap: arrêter · q: quitter\n")
	b.WriteString("Moteur audio: " + m.player.Engine() + "\n")
	return b.String()
}
