package social

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	atradio "github.com/tsirysndr/atradio.fm/sdk/go"
)

type Profile struct {
	DID         string `json:"did"`
	Handle      string `json:"handle"`
	DisplayName string `json:"displayName"`
	Description string `json:"description"`
	Stations    []atradio.StationView
	Favorites   []atradio.StationView
}

type PublicClient struct {
	BlueskyBase string
	ATRadioBase string
	HTTP        *http.Client
}

func NewPublicClient() *PublicClient {
	return &PublicClient{
		BlueskyBase: "https://public.api.bsky.app", ATRadioBase: atradio.DefaultAppView,
		HTTP: &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *PublicClient) Profile(ctx context.Context, actor string) (*Profile, error) {
	actor = strings.TrimSpace(actor)
	if actor == "" {
		return nil, fmt.Errorf("profil manquant")
	}
	profile := &Profile{}
	if err := c.get(ctx, c.BlueskyBase+"/xrpc/app.bsky.actor.getProfile?actor="+url.QueryEscape(actor), profile); err != nil {
		return nil, fmt.Errorf("profil ATProto: %w", err)
	}
	appview := atradio.NewAppView(c.ATRadioBase)
	appview.Client = c.HTTP
	stations, err := appview.Stations(ctx, actor, 100)
	if err != nil {
		return nil, fmt.Errorf("stations publiques: %w", err)
	}
	favorites, err := appview.Favorites(ctx, actor, 100)
	if err != nil {
		return nil, fmt.Errorf("favoris publics: %w", err)
	}
	profile.Stations, profile.Favorites = stations.Items, favorites.Items
	return profile, nil
}

func (c *PublicClient) get(ctx context.Context, endpoint string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("HTTP %s", resp.Status)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}
