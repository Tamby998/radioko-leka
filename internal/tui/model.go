package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
	"radioko-leka/internal/store"
)

type screen int

const (
	screenMadagascar screen = iota
	screenSearch
	screenResults
	screenFavorites
	screenNowPlaying
)

type stationResult struct {
	stations []radio.Station
	title    string
	screen   screen
	err      error
}

type Model struct {
	client    *radio.Client
	player    *player.Player
	favorites *store.Favorites
	screen    screen
	title     string
	query     string
	stations  []radio.Station
	cursor    int
	loading   bool
	message   string
	playing   *radio.Station
	width     int
}

func New(client *radio.Client, audio *player.Player, favorites *store.Favorites) Model {
	return Model{client: client, player: audio, favorites: favorites, screen: screenMadagascar,
		title: "Radios malgaches 🇲🇬", loading: true, message: "Chargement des radios malgaches…"}
}

func (m Model) Init() tea.Cmd { return madagascarCmd(m.client) }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
	case stationResult:
		m.loading = false
		if msg.err != nil {
			m.message = "Erreur: " + msg.err.Error()
			return m, nil
		}
		m.stations, m.title, m.screen, m.cursor = msg.stations, msg.title, msg.screen, 0
		m.message = fmt.Sprintf("%d station(s) disponible(s).", len(msg.stations))
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	name := key.String()
	if name == "ctrl+c" {
		m.player.Stop()
		return m, tea.Quit
	}
	if m.screen == screenSearch {
		return m.handleSearchKey(key)
	}
	switch name {
	case "q":
		m.player.Stop()
		return m, tea.Quit
	case "/", "s":
		m.screen, m.query, m.stations = screenSearch, "", nil
		m.title, m.message = "Recherche", "Tapez un nom puis appuyez sur Entrée."
	case "h":
		m.screen, m.loading = screenMadagascar, true
		m.title, m.message = "Radios malgaches 🇲🇬", "Chargement des radios malgaches…"
		return m, madagascarCmd(m.client)
	case "v":
		m.screen, m.stations, m.cursor = screenFavorites, m.favorites.List(), 0
		m.title, m.message = "Favoris", fmt.Sprintf("%d station(s) favorite(s).", len(m.stations))
	case "n":
		m.screen, m.title = screenNowPlaying, "En cours de lecture"
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor+1 < len(m.stations) {
			m.cursor++
		}
	case "left":
		volume, err := m.player.ChangeVolume(-5)
		m.setControlMessage(err, fmt.Sprintf("Volume: %d%%", volume))
	case "right":
		volume, err := m.player.ChangeVolume(5)
		m.setControlMessage(err, fmt.Sprintf("Volume: %d%%", volume))
	case " ":
		paused, err := m.player.TogglePause()
		text := "Lecture reprise."
		if paused {
			text = "Lecture en pause."
		}
		m.setControlMessage(err, text)
	case "m":
		muted, err := m.player.ToggleMute()
		text := "Son rétabli."
		if muted {
			text = "Son coupé."
		}
		m.setControlMessage(err, text)
	case "enter":
		m.playSelected()
	case "f":
		m.toggleFavorite()
	case "x", "esc":
		m.player.Stop()
		m.playing, m.message = nil, "Lecture arrêtée."
	}
	return m, nil
}

func (m Model) handleSearchKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch key.String() {
	case "esc":
		m.screen, m.loading = screenMadagascar, true
		m.title, m.message = "Radios malgaches 🇲🇬", "Chargement des radios malgaches…"
		return m, madagascarCmd(m.client)
	case "enter":
		if strings.TrimSpace(m.query) != "" {
			m.loading, m.message = true, "Recherche en cours…"
			return m, searchCmd(m.client, m.query)
		}
	case "backspace":
		if len(m.query) > 0 {
			m.query = m.query[:len(m.query)-1]
		}
	default:
		if len(key.Runes) > 0 {
			m.query += string(key.Runes)
		}
	}
	return m, nil
}

func (m *Model) playSelected() {
	if m.screen == screenNowPlaying || len(m.stations) == 0 {
		return
	}
	station := m.stations[m.cursor]
	if err := m.player.Play(station.URL); err != nil {
		m.message = "Erreur audio: " + err.Error()
		return
	}
	m.playing, m.message = &station, "Lecture de "+station.Name
}

func (m *Model) toggleFavorite() {
	if m.screen == screenNowPlaying && m.playing != nil {
		m.toggleStationFavorite(*m.playing)
		return
	}
	if len(m.stations) == 0 {
		return
	}
	m.toggleStationFavorite(m.stations[m.cursor])
	if m.screen == screenFavorites {
		m.stations = m.favorites.List()
		if m.cursor >= len(m.stations) && m.cursor > 0 {
			m.cursor--
		}
	}
}

func (m *Model) toggleStationFavorite(station radio.Station) {
	added, err := m.favorites.Toggle(station)
	if err != nil {
		m.message = "Erreur favoris: " + err.Error()
		return
	}
	if added {
		m.message = "Ajoutée aux favoris: " + station.Name
	} else {
		m.message = "Retirée des favoris: " + station.Name
	}
}

func (m *Model) setControlMessage(err error, success string) {
	if err != nil {
		m.message = "Erreur: " + err.Error()
	} else {
		m.message = success
	}
}

func madagascarCmd(client *radio.Client) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		stations, err := client.Madagascar(ctx, 50)
		return stationResult{stations: stations, title: "Radios malgaches 🇲🇬", screen: screenMadagascar, err: err}
	}
}

func searchCmd(client *radio.Client, query string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		stations, err := client.Search(ctx, query, 30)
		return stationResult{stations: stations, title: "Résultats · " + query, screen: screenResults, err: err}
	}
}

func (m Model) View() string {
	var b strings.Builder
	b.WriteString("RADIOKO LEKA — radio malagasy dans le terminal\n")
	b.WriteString("[h] Madagascar  [/] Recherche  [v] Favoris  [n] En cours\n\n")
	b.WriteString(m.title + "\n" + strings.Repeat("─", len([]rune(m.title))) + "\n")
	switch m.screen {
	case screenSearch:
		b.WriteString("Recherche : " + m.query + "█\n")
	case screenNowPlaying:
		b.WriteString(m.nowPlayingView())
	default:
		b.WriteString(m.stationListView())
	}
	if m.screen != screenNowPlaying && m.playing != nil {
		b.WriteString("\n" + m.compactPlayerView())
	}
	b.WriteString("\n" + m.message + "\n")
	b.WriteString("\n↑↓/jk choisir · Entrée lire · f favori · ←→ volume · Espace pause · m mute\n")
	b.WriteString("x arrêter · q quitter · Moteur: " + m.player.Engine() + "\n")
	return b.String()
}

func (m Model) stationListView() string {
	if m.loading {
		return "Chargement…\n"
	}
	if len(m.stations) == 0 {
		return "Aucune station dans cette liste.\n"
	}
	var b strings.Builder
	for index, station := range m.stations {
		cursor, favorite := "  ", " "
		if index == m.cursor {
			cursor = "> "
		}
		if m.favorites.Contains(station) {
			favorite = "★"
		}
		details := strings.Trim(strings.Join([]string{station.Country, station.Codec}, " · "), " ·")
		b.WriteString(fmt.Sprintf("%s%s %s  [%s]\n", cursor, favorite, station.Name, details))
	}
	return b.String()
}

func (m Model) compactPlayerView() string {
	volume, paused, muted := m.player.Status()
	state := "▶"
	if paused {
		state = "⏸"
	}
	sound := fmt.Sprintf("volume %d%%", volume)
	if muted {
		sound = "muet"
	}
	return fmt.Sprintf("%s %s · %s\n", state, m.playing.Name, sound)
}

func (m Model) nowPlayingView() string {
	if m.playing == nil {
		return "Aucune station en cours de lecture.\n"
	}
	favorite := "☆"
	if m.favorites.Contains(*m.playing) {
		favorite = "★"
	}
	return fmt.Sprintf("\n%s  %s\n%s%s · %s\n", favorite, m.playing.Name, m.compactPlayerView(), m.playing.Country, m.playing.Codec)
}
