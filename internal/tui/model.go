package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

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
	screenRecent
	screenNowPlaying
)

type stationResult struct {
	stations []radio.Station
	title    string
	screen   screen
	err      error
}

type splashDone struct{}

type Model struct {
	client    *radio.Client
	player    *player.Player
	favorites *store.Favorites
	history   *store.History
	settings  *store.Settings
	screen    screen
	title     string
	query     string
	stations  []radio.Station
	cursor    int
	loading   bool
	message   string
	playing   *radio.Station
	width     int
	booting   bool
}

func New(client *radio.Client, audio *player.Player, favorites *store.Favorites, history *store.History, settings *store.Settings) Model {
	return Model{client: client, player: audio, favorites: favorites, history: history, settings: settings, screen: screenMadagascar,
		title: "Radios malgaches 🇲🇬", loading: true, booting: true, message: "Chargement des radios malgaches…"}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(madagascarCmd(m.client), tea.Tick(1100*time.Millisecond, func(time.Time) tea.Msg { return splashDone{} }))
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
	case splashDone:
		m.booting = false
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
	case "r":
		m.screen, m.stations, m.cursor = screenRecent, m.history.List(), 0
		m.title, m.message = "Récemment écoutées", fmt.Sprintf("%d station(s) récente(s).", len(m.stations))
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
		if err == nil {
			err = m.settings.SetVolume(volume)
		}
		m.setControlMessage(err, fmt.Sprintf("Volume: %d%% · réglage sauvegardé", volume))
	case "right":
		volume, err := m.player.ChangeVolume(5)
		if err == nil {
			err = m.settings.SetVolume(volume)
		}
		m.setControlMessage(err, fmt.Sprintf("Volume: %d%% · réglage sauvegardé", volume))
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
	if err := m.history.Add(station); err != nil {
		m.message = "Lecture démarrée · historique non sauvegardé: " + err.Error()
	}
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
	if m.booting {
		return m.splashView()
	}
	var b strings.Builder
	header := lipgloss.JoinHorizontal(lipgloss.Center, brandStyle.Render("RADIOKO LEKA"), "  ", taglineStyle.Render("NY ONJAM-PEONTSIKA • NOTRE RADIO"))
	b.WriteString(header + "\n\n")
	b.WriteString(m.tabsView() + "\n\n")
	b.WriteString(titleStyle.Render(m.title) + "\n")
	switch m.screen {
	case screenSearch:
		b.WriteString(searchStyle.Width(m.contentWidth()-4).Render("🔎  "+m.query+"█") + "\n")
	case screenNowPlaying:
		b.WriteString(m.nowPlayingView())
	default:
		b.WriteString(m.stationListView())
	}
	if m.screen != screenNowPlaying && m.playing != nil {
		b.WriteString("\n" + m.compactPlayerView())
	}
	style := messageStyle
	if strings.HasPrefix(m.message, "Erreur") {
		style = errorStyle
	}
	b.WriteString("\n" + style.Render("● "+m.message) + "\n")
	b.WriteString("\n" + footerStyle.Render("↑↓/jk choisir  •  Entrée lire  •  f favori  •  ←→ volume") + "\n")
	b.WriteString(footerStyle.Render("Espace pause  •  m mute  •  x arrêter  •  q quitter") + "\n")
	b.WriteString(footerStyle.Render("moteur "+m.player.Engine()) + "\n")
	return lipgloss.NewStyle().Padding(1, 2).Render(b.String())
}

func (m Model) splashView() string {
	content := lipgloss.NewStyle().Foreground(red).Bold(true).Render(logo) + "\n\n" +
		taglineStyle.Render("RADIO MALAGASY • LIVE FROM MADAGASCAR") + "\n\n" +
		footerStyle.Render("Recherche des ondes malgaches…")
	width, height := m.width, 18
	if width < 1 {
		width = 80
	}
	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, content)
}

func (m Model) tabsView() string {
	tabs := []struct {
		label  string
		target screen
	}{
		{"H  Madagascar", screenMadagascar}, {"/  Recherche", screenSearch},
		{"V  Favoris", screenFavorites}, {"R  Récents", screenRecent}, {"N  En cours", screenNowPlaying},
	}
	parts := make([]string, 0, len(tabs))
	for _, tab := range tabs {
		style := tabStyle
		if m.screen == tab.target || (tab.target == screenSearch && m.screen == screenResults) {
			style = activeTab
		}
		parts = append(parts, style.Render(tab.label))
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, parts...)
}

func (m Model) contentWidth() int {
	if m.width <= 0 {
		return 76
	}
	width := m.width - 6
	if width < 40 {
		return 40
	}
	if width > 100 {
		return 100
	}
	return width
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
		mark := favorite
		if favorite == "★" {
			mark = favoriteMark.Render(favorite)
		}
		row := fmt.Sprintf("%s%s %-38s %s", cursor, mark, station.Name, detailStyle.Render(details))
		if index == m.cursor {
			row = selectedRow.Width(m.contentWidth() - 2).Render(row)
		}
		b.WriteString(row + "\n")
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
	return playerStyle.Width(m.contentWidth()-6).Render(fmt.Sprintf("%s  %s   •   %s", state, m.playing.Name, sound)) + "\n"
}

func (m Model) nowPlayingView() string {
	if m.playing == nil {
		return "Aucune station en cours de lecture.\n"
	}
	favorite := "☆"
	if m.favorites.Contains(*m.playing) {
		favorite = "★"
	}
	return fmt.Sprintf("\n%s  %s\n%s%s · %s\n", favoriteMark.Render(favorite), m.playing.Name, m.compactPlayerView(), detailStyle.Render(m.playing.Country), detailStyle.Render(m.playing.Codec))
}
