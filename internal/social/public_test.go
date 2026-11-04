package social

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPublicProfileAggregatesATProtoAndATRadio(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/xrpc/app.bsky.actor.getProfile":
			w.Write([]byte(`{"did":"did:plc:test","handle":"radio.test","displayName":"Radio Test","description":"On air"}`))
		case "/xrpc/fm.atradio.getStations":
			w.Write([]byte(`{"items":[{"uri":"at://station","station":{"stationId":"mg-1","name":"Radio MG","streamUrl":"https://example.com/live","source":"radio-browser"}}]}`))
		case "/xrpc/fm.atradio.getFavorites":
			w.Write([]byte(`{"items":[{"uri":"at://favorite","station":{"stationId":"mg-2","name":"Radio Favorite","streamUrl":"https://example.com/favorite","source":"radio-browser"}}]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := &PublicClient{BlueskyBase: server.URL, ATRadioBase: server.URL, HTTP: server.Client()}
	profile, err := client.Profile(context.Background(), "radio.test")
	if err != nil {
		t.Fatal(err)
	}
	if profile.DID != "did:plc:test" || len(profile.Stations) != 1 || len(profile.Favorites) != 1 {
		t.Fatalf("unexpected profile: %#v", profile)
	}
}
