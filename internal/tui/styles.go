package tui

import "github.com/charmbracelet/lipgloss"

var (
	red   = lipgloss.AdaptiveColor{Light: "#C62828", Dark: "#FF5F5F"}
	green = lipgloss.AdaptiveColor{Light: "#167A3E", Dark: "#55D187"}
	white = lipgloss.AdaptiveColor{Light: "#FFFFFF", Dark: "#F8F8F2"}
	muted = lipgloss.AdaptiveColor{Light: "#667085", Dark: "#7D8590"}
	dark  = lipgloss.AdaptiveColor{Light: "#20242A", Dark: "#161B22"}

	brandStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(white).
			Background(red).
			Padding(0, 2)
	taglineStyle = lipgloss.NewStyle().Foreground(green).Bold(true)
	titleStyle   = lipgloss.NewStyle().Foreground(green).Bold(true).MarginBottom(1)
	tabStyle     = lipgloss.NewStyle().Foreground(muted).Padding(0, 1)
	activeTab    = lipgloss.NewStyle().Foreground(white).Background(green).Bold(true).Padding(0, 1)
	selectedRow  = lipgloss.NewStyle().Foreground(white).Background(dark).Bold(true).Padding(0, 1)
	favoriteMark = lipgloss.NewStyle().Foreground(red).Bold(true)
	detailStyle  = lipgloss.NewStyle().Foreground(muted)
	messageStyle = lipgloss.NewStyle().Foreground(green)
	errorStyle   = lipgloss.NewStyle().Foreground(red).Bold(true)
	footerStyle  = lipgloss.NewStyle().Foreground(muted)
	playerStyle  = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(green).Padding(0, 2)
	searchStyle  = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(red).Padding(0, 1)
)

const logo = `
 ██████╗  █████╗ ██████╗ ██╗ ██████╗ ██╗  ██╗ ██████╗
 ██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗██║ ██╔╝██╔═══██╗
 ██████╔╝███████║██║  ██║██║██║   ██║█████╔╝ ██║   ██║
 ██╔══██╗██╔══██║██║  ██║██║██║   ██║██╔═██╗ ██║   ██║
 ██║  ██║██║  ██║██████╔╝██║╚██████╔╝██║  ██╗╚██████╔╝
 ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝`
