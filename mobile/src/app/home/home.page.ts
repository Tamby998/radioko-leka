import { Component, ElementRef, ViewChild } from '@angular/core';

type Tab = 'home' | 'search' | 'library';
type Station = {
  id: string;
  name: string;
  detail: string;
  country: string;
  stream: string;
  color: string;
};

const MALAGASY_STATIONS: Station[] = [
  {
    id: 'olivasoa',
    name: 'Olivasoa Radio',
    detail: '91.0 FM · Gospel',
    country: 'Madagascar',
    stream: 'https://live.webradio.mg/listen/olivasoa/radio.mp3',
    color: 'mint',
  },
  {
    id: 'djbam',
    name: 'DJ Bam',
    detail: 'Afro House · Webradio',
    country: 'Madagascar',
    stream: 'https://live.webradio.mg/listen/djbam/radio.mp3',
    color: 'violet',
  },
  {
    id: 'vazogasy',
    name: 'Radio Vazo Gasy',
    detail: 'Hira gasy · Variété',
    country: 'Madagascar',
    stream: 'https://stream.radiovazogasy.com/stream?1.mp3',
    color: 'blue',
  },
  {
    id: 'topradio',
    name: 'Top Radio',
    detail: '102.8 FM · Hits',
    country: 'Madagascar',
    stream: 'https://listen.radioking.com/radio/309053/stream/356036',
    color: 'orange',
  },
  {
    id: 'rockmada',
    name: 'Radio Rock Madagascar',
    detail: 'Rock · Metal',
    country: 'Madagascar',
    stream: 'https://tanjona.radioca.st/stream',
    color: 'pink',
  },
  {
    id: 'hopefy',
    name: 'Hopefy Radio MG',
    detail: 'Gospel · Chrétien',
    country: 'Madagascar',
    stream:
      'https://hopefy.fanantenanahoanao.org/listen/hopefy_radio_mg/radio.mp3',
    color: 'teal',
  },
];

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
  standalone: false,
})
export class HomePage {
  @ViewChild('audio') private audio?: ElementRef<HTMLAudioElement>;
  readonly featured = MALAGASY_STATIONS;
  activeTab: Tab = 'home';
  current = MALAGASY_STATIONS[0];
  playing = false;
  playerOpen = false;
  loading = false;
  query = '';
  searchResults: Station[] = [];
  favorites = new Set<string>(this.readIds('radiokoleka-mobile:favorites'));
  recent = this.readRecent();

  get favoriteStations(): Station[] {
    const known = [...MALAGASY_STATIONS, ...this.searchResults];
    return known.filter(
      (station, index) =>
        this.favorites.has(station.id) &&
        known.findIndex((item) => item.id === station.id) === index,
    );
  }
  setTab(tab: Tab): void {
    this.activeTab = tab;
    this.playerOpen = false;
  }
  async selectStation(station: Station): Promise<void> {
    if (this.current.id !== station.id) {
      this.recent = [
        this.current,
        ...this.recent.filter((item) => item.id !== this.current.id),
      ].slice(0, 12);
      localStorage.setItem(
        'radiokoleka-mobile:recent',
        JSON.stringify(this.recent),
      );
      this.current = station;
    }
    setTimeout(() => void this.play(), 0);
  }
  async togglePlayback(event?: Event): Promise<void> {
    event?.stopPropagation();
    const element = this.audio?.nativeElement;
    if (!element) return;
    if (element.paused) await this.play();
    else element.pause();
  }
  toggleFavorite(station: Station, event?: Event): void {
    event?.stopPropagation();
    this.favorites.has(station.id)
      ? this.favorites.delete(station.id)
      : this.favorites.add(station.id);
    localStorage.setItem(
      'radiokoleka-mobile:favorites',
      JSON.stringify([...this.favorites]),
    );
  }
  isFavorite(station: Station): boolean {
    return this.favorites.has(station.id);
  }
  changeStation(direction: -1 | 1): void {
    const pool =
      this.searchResults.length && this.activeTab === 'search'
        ? this.searchResults
        : MALAGASY_STATIONS;
    const index = pool.findIndex((station) => station.id === this.current.id);
    void this.selectStation(
      pool[(Math.max(index, 0) + direction + pool.length) % pool.length],
    );
  }
  runQuickSearch(query: string): void {
    this.query = query;
    void this.performSearch(query);
  }
  async search(event: Event): Promise<void> {
    this.query = (event.target as HTMLInputElement).value;
    await this.performSearch(this.query);
  }
  trackStation(_: number, station: Station): string {
    return station.id;
  }

  private async performSearch(rawQuery: string): Promise<void> {
    const query = rawQuery.trim();
    if (query.length < 2) {
      this.searchResults = [];
      return;
    }
    this.loading = true;
    try {
      const response = await fetch(
        `https://all.api.radio-browser.info/json/stations/search?name=${encodeURIComponent(query)}&hidebroken=true&order=votes&reverse=true&limit=40`,
      );
      if (!response.ok) throw new Error('search unavailable');
      const values = (await response.json()) as Array<Record<string, unknown>>;
      this.searchResults = values
        .filter((item) =>
          String(item['url_resolved'] ?? '').startsWith('https://'),
        )
        .map((item, index) => ({
          id: String(item['stationuuid']),
          name: String(item['name']).trim(),
          detail: `${Number(item['bitrate']) || 'Web'}${Number(item['bitrate']) ? ' kbps' : ''} · ${String(item['codec'] || 'Audio')}`,
          country: String(item['country'] || 'International'),
          stream: String(item['url_resolved']),
          color: ['mint', 'violet', 'blue', 'orange', 'pink', 'teal'][
            index % 6
          ],
        }));
    } catch {
      this.searchResults = MALAGASY_STATIONS.filter((station) =>
        station.name.toLowerCase().includes(query.toLowerCase()),
      );
    } finally {
      this.loading = false;
    }
  }
  private async play(): Promise<void> {
    const element = this.audio?.nativeElement;
    if (!element) return;
    try {
      await element.play();
      this.playing = true;
    } catch {
      this.playing = false;
    }
  }
  private readIds(key: string): string[] {
    try {
      return JSON.parse(localStorage.getItem(key) ?? '[]') as string[];
    } catch {
      return [];
    }
  }
  private readRecent(): Station[] {
    try {
      return JSON.parse(
        localStorage.getItem('radiokoleka-mobile:recent') ?? '[]',
      ) as Station[];
    } catch {
      return [];
    }
  }
}
