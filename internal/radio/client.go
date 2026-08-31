package radio

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

const defaultEndpoint = "https://all.api.radio-browser.info"

type Station struct {
	ID          string `json:"stationuuid"`
	Name        string `json:"name"`
	URL         string `json:"url_resolved"`
	Country     string `json:"country"`
	CountryCode string `json:"countrycode"`
	Language    string `json:"language"`
	Codec       string `json:"codec"`
	Bitrate     int    `json:"bitrate"`
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

	stations, err := c.get(ctx, "/json/stations/search?"+params.Encode())
	if err != nil {
		return nil, err
	}
	// Les radios malgaches restent en tête lorsqu'elles correspondent à la recherche.
	sort.SliceStable(stations, func(i, j int) bool {
		return strings.EqualFold(stations[i].CountryCode, "MG") && !strings.EqualFold(stations[j].CountryCode, "MG")
	})
	return stations, nil
}

func (c *Client) Madagascar(ctx context.Context, limit int) ([]Station, error) {
	if limit < 1 {
		limit = 50
	}
	params := url.Values{}
	params.Set("hidebroken", "true")
	params.Set("order", "votes")
	params.Set("reverse", "true")
	params.Set("limit", strconv.Itoa(limit))
	return c.get(ctx, "/json/stations/bycountrycodeexact/MG?"+params.Encode())
}

func (c *Client) get(ctx context.Context, path string) ([]Station, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.endpoint+path, nil)
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
