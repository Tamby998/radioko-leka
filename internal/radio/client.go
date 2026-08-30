package radio

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const defaultEndpoint = "https://all.api.radio-browser.info"

type Station struct {
	ID       string `json:"stationuuid"`
	Name     string `json:"name"`
	URL      string `json:"url_resolved"`
	Country  string `json:"country"`
	Language string `json:"language"`
	Codec    string `json:"codec"`
	Bitrate  int    `json:"bitrate"`
}

type Client struct {
	endpoint string
	http     *http.Client
}

func NewClient() *Client {
	return &Client{
		endpoint: defaultEndpoint,
		http:     &http.Client{Timeout: 12 * time.Second},
	}
}

func (c *Client) Search(ctx context.Context, query string, limit int) ([]Station, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	if limit < 1 {
		limit = 20
	}

	params := url.Values{}
	params.Set("name", query)
	params.Set("nameExact", "false")
	params.Set("hidebroken", "true")
	params.Set("order", "votes")
	params.Set("reverse", "true")
	params.Set("limit", strconv.Itoa(limit))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.endpoint+"/json/stations/search?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "radioko-leka/0.1")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("recherche des stations: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Radio Browser a répondu %s", resp.Status)
	}

	var stations []Station
	if err := json.NewDecoder(resp.Body).Decode(&stations); err != nil {
		return nil, fmt.Errorf("lecture de la réponse: %w", err)
	}

	result := stations[:0]
	for _, station := range stations {
		station.Name = strings.TrimSpace(station.Name)
		if station.Name != "" && station.URL != "" {
			result = append(result, station)
		}
	}
	return result, nil
}
