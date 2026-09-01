import { CommonModule } from '@angular/common';
import { Component, ElementRef, ViewChild, computed, signal } from '@angular/core';

type Station = {
  id: string;
  name: string;
  frequency: string;
  genre: string;
  city: string;
  country: string;
  codec: string;
  stream: string;
  color: string;
};
type Country = { name: string; code: string; count: number };
type RadioBrowserStation = {
  stationuuid: string;
  name: string;
  url_resolved: string;
  country: string;
  codec: string;
  bitrate: number;
  tags: string;
  state: string;
};

@Component({
  selector: 'app-root',
  imports: [CommonModule],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  @ViewChild('audio') private audio?: ElementRef<HTMLAudioElement>;
  private readonly localStations: Station[] = [
    {
      id: 'olivasoa',
      name: 'Olivasoa Radio',
      frequency: '91.0 FM',
      genre: 'Gospel · Malagasy',
      city: 'Antananarivo',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://live.webradio.mg/listen/olivasoa/radio.mp3',
      color: 'mint',
    },
    {
      id: 'djbam',
      name: 'DJ Bam',
      frequency: 'Webradio',
      genre: 'House · Afro House',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://live.webradio.mg/listen/djbam/radio.mp3',
      color: 'violet',
    },
    {
      id: 'vazogasy',
      name: 'Radio Vazo Gasy',
      frequency: 'Webradio',
      genre: 'Hira gasy · Variété',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://stream.radiovazogasy.com/stream?1.mp3',
      color: 'blue',
    },
    {
      id: 'topradio',
      name: 'Top Radio',
      frequency: '102.8 FM',
      genre: 'Pop · Hits',
      city: 'Antananarivo',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://listen.radioking.com/radio/309053/stream/356036',
      color: 'orange',
    },
    {
      id: 'rockmada',
      name: 'Radio Rock Madagascar',
      frequency: 'Webradio',
      genre: 'Rock · Metal',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://tanjona.radioca.st/stream',
      color: 'pink',
    },
    {
      id: 'rdj',
      name: 'Radio des jeunes (RDJ)',
      frequency: '96.6 FM',
      genre: 'Pop · Hits',
      city: 'Antananarivo',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'http://rdj966.net:8000/rdj966.mp3',
      color: 'orange',
    },
    {
      id: 'don-bosco',
      name: 'Radio Don Bosco',
      frequency: '93.4 FM',
      genre: 'Chrétien · Éducation',
      city: 'Antananarivo',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'http://onair15.xdevel.com:9248/;',
      color: 'blue',
    },
    {
      id: 'rna-madagascar',
      name: 'RNA Madagascar',
      frequency: 'Webradio',
      genre: 'Actualités · Généraliste',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'http://drs-live-rna.gasy-internet.info:9001/;',
      color: 'mint',
    },
    {
      id: 'hopefy',
      name: 'Hopefy Radio MG',
      frequency: 'Webradio',
      genre: 'Chrétien · Gospel',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://hopefy.fanantenanahoanao.org/listen/hopefy_radio_mg/radio.mp3',
      color: 'violet',
    },
    {
      id: 'esdes',
      name: 'ESDES Radio',
      frequency: 'Webradio',
      genre: 'Éducation · Jazz',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://esdesradio.netpro.tv/listen/esdes_radio/radio.mp3',
      color: 'blue',
    },
    {
      id: 'oasis',
      name: 'Radio Oasis',
      frequency: 'Webradio',
      genre: 'Chrétien · Gospel',
      city: 'Antananarivo',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://hopefy.fanantenanahoanao.org/listen/radiooasistana/radio.mp3',
      color: 'mint',
    },
    {
      id: 'hifi',
      name: 'Radio HIFI',
      frequency: 'Webradio',
      genre: 'Musique · Variété',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://listen.radioking.com/radio/52108/stream/89122',
      color: 'orange',
    },
    {
      id: 'feon-ny-filazantsara',
      name: "Radio Feon'ny Filazantsara",
      frequency: 'Webradio',
      genre: 'Chrétien · Éducation',
      city: 'Madagascar',
      country: 'Madagascar',
      codec: 'MP3',
      stream: 'https://fpsnew1.listen2myradio.com:2199/listen.php?ip=82.145.63.6&port=8622&type=s1',
      color: 'pink',
    },
  ];
  private readonly remoteStations = signal<Station[]>([]);
  protected readonly stations = computed(() =>
    this.remoteStations().length > 0 ? this.remoteStations() : this.localStations,
  );
  protected readonly current = signal(this.localStations[0]);
  protected readonly playing = signal(false);
  protected readonly muted = signal(false);
  protected readonly volume = signal(72);
  protected readonly query = signal('');
  protected readonly selectedCountry = signal('MG');
  protected readonly selectedGenre = signal('Tous les genres');
  protected readonly countryOptions = signal<Country[]>([
    { name: 'Madagascar', code: 'MG', count: this.localStations.length },
  ]);
  protected readonly loadingStations = signal(false);
  protected readonly loadingCountries = signal(false);
  protected readonly pageSize = 50;
  protected readonly hasMore = signal(true);
  private readonly page = signal(0);
  protected readonly favorites = signal<Set<string>>(this.loadFavorites());
  protected readonly recent = signal<Station[]>([]);
  protected readonly genres = computed(() => [
    'Tous les genres',
    ...new Set(this.stations().flatMap((station) => station.genre.split(' · '))),
  ]);
  protected readonly selectedCountryName = computed(
    () =>
      this.countryOptions().find((country) => country.code === this.selectedCountry())?.name ??
      this.selectedCountry(),
  );
  protected readonly filteredStations = computed(() => {
    const query = this.query().trim().toLocaleLowerCase();
    return this.stations().filter((station) => {
      const matchesQuery =
        !query ||
        `${station.name} ${station.genre} ${station.city} ${station.country} ${station.codec}`
          .toLocaleLowerCase()
          .includes(query);
      const matchesGenre =
        this.selectedGenre() === 'Tous les genres' ||
        station.genre.split(' · ').includes(this.selectedGenre());
      return matchesQuery && matchesGenre;
    });
  });

  constructor() {
    void this.loadCountries();
    void this.loadStations(true);
  }

  protected async selectStation(station: Station): Promise<void> {
    if (station.id === this.current().id) return this.togglePlayback();
    const previous = this.current();
    this.current.set(station);
    this.recent.update((items) =>
      [previous, ...items.filter((item) => item.id !== previous.id)].slice(0, 4),
    );
    this.playing.set(true);
    setTimeout(() => {
      const playback = this.audio?.nativeElement.play();
      void playback?.catch(() => this.playing.set(false));
    });
  }
  protected changeStation(direction: -1 | 1): void {
    const stations = this.filteredStations();
    if (stations.length === 0) return;
    const currentIndex = stations.findIndex((station) => station.id === this.current().id);
    const startIndex = currentIndex < 0 ? (direction === 1 ? -1 : 0) : currentIndex;
    const nextIndex = (startIndex + direction + stations.length) % stations.length;
    void this.selectStation(stations[nextIndex]);
  }
  protected async togglePlayback(): Promise<void> {
    const player = this.audio?.nativeElement;
    if (!player) return;
    if (player.paused)
      await Promise.resolve(player.play())
        .then(() => this.playing.set(true))
        .catch(() => this.playing.set(false));
    else {
      player.pause();
      this.playing.set(false);
    }
  }
  protected setVolume(event: Event): void {
    const value = Number((event.target as HTMLInputElement).value);
    this.volume.set(value);
    if (this.audio) this.audio.nativeElement.volume = value / 100;
    if (value > 0) this.muted.set(false);
  }
  protected toggleMute(): void {
    this.muted.update((value) => !value);
    if (this.audio) this.audio.nativeElement.muted = this.muted();
  }
  protected setQuery(event: Event): void {
    this.query.set((event.target as HTMLInputElement).value);
  }
  protected setCountry(event: Event): void {
    this.selectedCountry.set((event.target as HTMLSelectElement).value);
    this.selectedGenre.set('Tous les genres');
    this.query.set('');
    void this.loadStations(true);
  }
  protected setGenre(event: Event): void {
    this.selectedGenre.set((event.target as HTMLSelectElement).value);
  }
  protected toggleFavorite(station: Station, event?: Event): void {
    event?.stopPropagation();
    const next = new Set(this.favorites());
    next.has(station.id) ? next.delete(station.id) : next.add(station.id);
    this.favorites.set(next);
    localStorage.setItem('radioko-leka:favorites', JSON.stringify([...next]));
  }
  protected isFavorite(station: Station): boolean {
    return this.favorites().has(station.id);
  }
  protected loadMore(): void {
    if (!this.loadingStations() && this.hasMore()) void this.loadStations(false);
  }
  private async loadCountries(): Promise<void> {
    this.loadingCountries.set(true);
    try {
      const response = await fetch(
        'https://all.api.radio-browser.info/json/countries?order=stationcount&reverse=true&hidebroken=true',
      );
      if (!response.ok) throw new Error('countries unavailable');
      const values = (await response.json()) as Array<{
        name: string;
        iso_3166_1: string;
        stationcount: number;
      }>;
      const countries = values
        .filter((country) => country.iso_3166_1 && country.stationcount > 0)
        .map((country) => ({
          name: country.iso_3166_1 === 'MG' ? 'Madagascar' : country.name,
          code: country.iso_3166_1,
          count: country.stationcount,
        }));
      countries.sort((a, b) => (a.code === 'MG' ? -1 : b.code === 'MG' ? 1 : b.count - a.count));
      this.countryOptions.set(countries);
    } catch {
      // Le catalogue malgache embarqué reste disponible hors connexion.
    } finally {
      this.loadingCountries.set(false);
    }
  }
  private async loadStations(reset: boolean): Promise<void> {
    if (this.loadingStations()) return;
    this.loadingStations.set(true);
    const nextPage = reset ? 0 : this.page() + 1;
    try {
      const offset = nextPage * this.pageSize;
      const code = encodeURIComponent(this.selectedCountry());
      const response = await fetch(
        `https://all.api.radio-browser.info/json/stations/bycountrycodeexact/${code}?hidebroken=true&order=votes&reverse=true&limit=${this.pageSize}&offset=${offset}`,
      );
      if (!response.ok) throw new Error('stations unavailable');
      const values = (await response.json()) as RadioBrowserStation[];
      const mapped = values
        .filter((station) => station.name !== 'Abdulbasit Abdulsamad')
        .map((station, index) => this.mapStation(station, offset + index));
      const base = reset
        ? this.selectedCountry() === 'MG'
          ? this.localStations
          : []
        : this.remoteStations();
      this.remoteStations.set(this.deduplicateStations([...base, ...mapped]));
      this.page.set(nextPage);
      this.hasMore.set(values.length === this.pageSize);
    } catch {
      if (reset && this.selectedCountry() === 'MG') this.remoteStations.set(this.localStations);
      this.hasMore.set(false);
    } finally {
      this.loadingStations.set(false);
    }
  }
  private mapStation(station: RadioBrowserStation, index: number): Station {
    const genres = station.tags
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean)
      .slice(0, 2)
      .map((tag) => tag.charAt(0).toLocaleUpperCase() + tag.slice(1));
    return {
      id: station.stationuuid,
      name: station.name.trim(),
      frequency: station.bitrate > 0 ? `${station.bitrate} kbps` : 'Webradio',
      genre: genres.join(' · ') || 'Généraliste',
      city: station.state || station.country,
      country: station.country || this.selectedCountry(),
      codec: station.codec || 'Audio',
      stream: station.url_resolved,
      color: ['mint', 'violet', 'blue', 'orange', 'pink'][index % 5],
    };
  }
  private deduplicateStations(stations: Station[]): Station[] {
    const names = new Set<string>();
    const streams = new Set<string>();
    return stations.filter((station) => {
      const name = station.name
        .toLocaleLowerCase()
        .replace(/^radio\s+/, '')
        .trim();
      const stream = station.stream.replace(/;stream\.mp3$/, ';');
      if (names.has(name) || streams.has(stream)) return false;
      names.add(name);
      streams.add(stream);
      return true;
    });
  }
  private loadFavorites(): Set<string> {
    try {
      return new Set(JSON.parse(localStorage.getItem('radioko-leka:favorites') ?? '[]'));
    } catch {
      return new Set();
    }
  }
}
