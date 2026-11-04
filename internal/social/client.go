package social

import (
	"context"
	"fmt"
	"os"

	atradio "github.com/tsirysndr/atradio.fm/sdk/go"

	"radioko-leka/internal/radio"
	"radioko-leka/internal/store"
)

type Client struct {
	agent *atradio.Agent
}

type SyncResult struct {
	Uploaded   int
	Downloaded int
	DID        string
}

func LoginFromEnv(ctx context.Context) (*Client, error) {
	identifier := os.Getenv("RADIOKO_ATPROTO_IDENTIFIER")
	password := os.Getenv("RADIOKO_ATPROTO_APP_PASSWORD")
	if identifier == "" || password == "" {
		return nil, fmt.Errorf("définissez RADIOKO_ATPROTO_IDENTIFIER et RADIOKO_ATPROTO_APP_PASSWORD")
	}
	agent, err := atradio.Login(ctx, atradio.LoginOptions{
		Service: os.Getenv("RADIOKO_ATPROTO_SERVICE"), Identifier: identifier, Password: password,
	})
	if err != nil {
		return nil, fmt.Errorf("connexion ATProto: %w", err)
	}
	return &Client{agent: agent}, nil
}

func (c *Client) SyncFavorites(ctx context.Context, favorites *store.Favorites) (SyncResult, error) {
	result := SyncResult{DID: c.agent.Did()}
	remote, err := c.agent.AppView.Favorites(ctx, c.agent.Did(), 100)
	if err != nil {
		return result, fmt.Errorf("lecture des favoris PDS: %w", err)
	}
	for _, item := range remote.Items {
		added, err := favorites.Ensure(fromStationInfo(item.Station))
		if err != nil {
			return result, err
		}
		if added {
			result.Downloaded++
		}
	}
	for _, station := range favorites.List() {
		if _, err := c.agent.Favorite(ctx, toStationInfo(station)); err != nil {
			return result, fmt.Errorf("écriture du favori %q: %w", station.Name, err)
		}
		result.Uploaded++
	}
	return result, nil
}

func toStationInfo(station radio.Station) atradio.StationInfo {
	return atradio.StationInfo{
		StationID: station.ID, Name: station.Name, StreamURL: station.URL,
		Source: "radio-browser", Country: station.Country, Language: station.Language,
		Bitrate: station.Bitrate, Codec: station.Codec,
	}
}

func fromStationInfo(station atradio.StationInfo) radio.Station {
	return radio.Station{
		ID: station.StationID, Name: station.Name, URL: station.StreamURL,
		Country: station.Country, Language: station.Language, Bitrate: station.Bitrate, Codec: station.Codec,
	}
}
