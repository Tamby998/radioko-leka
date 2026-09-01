package radio

import "testing"

func TestCuratedMadagascarStations(t *testing.T) {
	stations := curatedMadagascarStations()
	if len(stations) < 2 {
		t.Fatalf("expected at least two curated stations, got %d", len(stations))
	}
	for _, station := range stations {
		if station.CountryCode != "MG" {
			t.Fatalf("station %q has country code %q", station.Name, station.CountryCode)
		}
		if station.URL == "" {
			t.Fatalf("station %q has no stream URL", station.Name)
		}
	}
}

func TestSearchCuratedMadagascar(t *testing.T) {
	stations := searchCuratedMadagascar("oliva")
	if len(stations) != 1 || stations[0].Name != "Olivasoa Radio" {
		t.Fatalf("unexpected search result: %#v", stations)
	}
}

func TestMergeStationsDeduplicatesAndLimits(t *testing.T) {
	primary := []Station{{Name: "Olivasoa Radio", URL: "https://example.com/olivasoa"}}
	additions := []Station{
		{Name: "Olivasoa Radio", URL: "https://example.com/duplicate-name"},
		{Name: "Autre radio", URL: "https://example.com/olivasoa"},
		{Name: "DJ Bam", URL: "https://example.com/djbam"},
	}
	stations := mergeStations(primary, additions, 2)
	if len(stations) != 2 {
		t.Fatalf("expected two unique stations, got %d", len(stations))
	}
	if stations[1].Name != "DJ Bam" {
		t.Fatalf("unexpected second station: %#v", stations[1])
	}
}
