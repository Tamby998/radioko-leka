package main

import (
	"context"
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"radioko-leka/internal/player"
	"radioko-leka/internal/radio"
	"radioko-leka/internal/social"
	"radioko-leka/internal/store"
	"radioko-leka/internal/tui"
)

func main() {
	var err error
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "sync":
			err = runSync()
		case "profile":
			if len(os.Args) < 3 {
				err = fmt.Errorf("usage: radioko-leka profile <handle|did>")
			} else {
				err = runProfile(os.Args[2])
			}
		case "help", "-h", "--help":
			printUsage()
			return
		default:
			err = fmt.Errorf("commande inconnue %q", os.Args[1])
		}
	} else {
		err = runTUI()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "radioko-leka:", err)
		os.Exit(1)
	}
}

func runTUI() error {
	settings, err := store.OpenSettings("")
	if err != nil {
		return err
	}
	audio := player.NewWithVolume(settings.Data().Volume)
	favorites, err := store.OpenFavorites("")
	if err != nil {
		return err
	}
	history, err := store.OpenHistory("", settings.Data().RecentLimit)
	if err != nil {
		return err
	}
	program := tea.NewProgram(tui.New(radio.NewClient(), audio, favorites, history, settings), tea.WithAltScreen())
	_, err = program.Run()
	return err
}

func runSync() error {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	favorites, err := store.OpenFavorites("")
	if err != nil {
		return err
	}
	client, err := social.LoginFromEnv(ctx)
	if err != nil {
		return err
	}
	result, err := client.SyncFavorites(ctx, favorites)
	if err != nil {
		return err
	}
	fmt.Printf("Synchronisation terminée pour %s : %d envoyé(s), %d importé(s).\n", result.DID, result.Uploaded, result.Downloaded)
	return nil
}

func runProfile(actor string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	profile, err := social.NewPublicClient().Profile(ctx, actor)
	if err != nil {
		return err
	}
	fmt.Printf("%s (@%s)\n%s\nDID: %s\n\n", profile.DisplayName, profile.Handle, profile.Description, profile.DID)
	fmt.Printf("Stations publiques (%d)\n", len(profile.Stations))
	for _, item := range profile.Stations {
		fmt.Printf("  • %s — %s\n", item.Station.Name, item.Station.StreamURL)
	}
	fmt.Printf("\nFavoris publics (%d)\n", len(profile.Favorites))
	for _, item := range profile.Favorites {
		fmt.Printf("  ★ %s\n", item.Station.Name)
	}
	return nil
}

func printUsage() {
	fmt.Println(`radioko-leka — radio malagasy dans le terminal

Usage:
  radioko-leka                  lancer l'interface terminal
  radioko-leka profile ACTOR    afficher un profil et ses stations publiques
  radioko-leka sync             synchroniser les favoris avec le PDS

Connexion pour sync:
  RADIOKO_ATPROTO_IDENTIFIER    handle, DID ou email
  RADIOKO_ATPROTO_APP_PASSWORD  app-password ATProto
  RADIOKO_ATPROTO_SERVICE       PDS optionnel (défaut: https://bsky.social)`)
}
