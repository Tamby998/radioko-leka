package radio

import "strings"

// curatedMadagascar complète Radio Browser avec des flux malgaches vérifiés.
// Les URL pointent directement vers les flux audio officiels des radios.
var curatedMadagascar = []Station{
	{ID: "mg-olivasoa", Name: "Olivasoa Radio", URL: "https://live.webradio.mg/listen/olivasoa/radio.mp3", Country: "Madagascar", CountryCode: "MG", Language: "Malagasy", Codec: "MP3"},
	{ID: "mg-dj-bam", Name: "DJ Bam", URL: "https://live.webradio.mg/listen/djbam/radio.mp3", Country: "Madagascar", CountryCode: "MG", Language: "Malagasy", Codec: "MP3"},
}

func curatedMadagascarStations() []Station {
	stations := make([]Station, len(curatedMadagascar))
	copy(stations, curatedMadagascar)
	return stations
}

func searchCuratedMadagascar(query string) []Station {
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		return nil
	}
	var result []Station
	for _, station := range curatedMadagascar {
		if strings.Contains(strings.ToLower(station.Name), query) {
			result = append(result, station)
		}
	}
	return result
}

func mergeStations(primary, additions []Station, limit int) []Station {
	result := make([]Station, 0, len(primary)+len(additions))
	seenURLs := make(map[string]struct{}, len(primary)+len(additions))
	seenNames := make(map[string]struct{}, len(primary)+len(additions))
	appendStation := func(station Station) {
		urlKey := strings.ToLower(strings.TrimSpace(station.URL))
		nameKey := strings.ToLower(strings.TrimSpace(station.Name))
		if urlKey == "" || nameKey == "" {
			return
		}
		if _, exists := seenURLs[urlKey]; exists {
			return
		}
		if _, exists := seenNames[nameKey]; exists {
			return
		}
		seenURLs[urlKey] = struct{}{}
		seenNames[nameKey] = struct{}{}
		result = append(result, station)
	}
	for _, station := range primary {
		appendStation(station)
	}
	for _, station := range additions {
		appendStation(station)
	}
	if limit > 0 && len(result) > limit {
		return result[:limit]
	}
	return result
}
