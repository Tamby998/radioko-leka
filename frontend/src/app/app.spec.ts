import { TestBed } from '@angular/core/testing';
import { afterEach, vi } from 'vitest';
import { App } from './app';
describe('App', () => {
  beforeEach(async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline test')));
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
  });
  afterEach(() => vi.unstubAllGlobals());
  it('creates the radio application', () => {
    expect(TestBed.createComponent(App).componentInstance).toBeTruthy();
  });
  it('renders the Malagasy radio catalog', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Radios malgaches');
    expect(fixture.nativeElement.textContent).toContain('Olivasoa Radio');
    expect(fixture.nativeElement.querySelectorAll('.station-card').length).toBe(13);
  });

  it('selects the next station from the player controls', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const audio: HTMLAudioElement = fixture.nativeElement.querySelector('audio');
    audio.play = vi.fn().mockResolvedValue(undefined);
    const nextButton: HTMLButtonElement = fixture.nativeElement.querySelector(
      '[aria-label="Station suivante"]',
    );
    nextButton.click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.player-info h2').textContent).toContain('DJ Bam');
  });
});
