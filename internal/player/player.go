package player

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

type Player struct {
	mu        sync.Mutex
	cmd       *exec.Cmd
	ipcPath   string
	engine    string
	volume    int
	paused    bool
	muted     bool
	streaming bool
}

func New() *Player {
	return &Player{engine: findEngine(), volume: 70}
}

func findEngine() string {
	for _, name := range []string{"mpv", "ffplay", "vlc"} {
		if path, err := exec.LookPath(name); err == nil {
			return path
		}
	}
	return ""
}

func (p *Player) Engine() string {
	if p.engine == "" {
		return "aucun"
	}
	return p.engine
}

func (p *Player) Play(streamURL string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.engine == "" {
		return fmt.Errorf("aucun lecteur trouvé; installez mpv (macOS: brew install mpv)")
	}
	switch base := filepathBase(p.engine); base {
	case "mpv":
		if p.cmd == nil {
			if err := p.startMPVLocked(); err != nil {
				return err
			}
		}
		if err := p.sendLocked("loadfile", streamURL, "replace"); err != nil {
			return err
		}
		_ = p.sendLocked("set_property", "volume", p.volume)
		_ = p.sendLocked("set_property", "pause", false)
		p.paused = false
		p.streaming = true
		return nil
	case "ffplay":
		return p.startSimpleLocked([]string{"-nodisp", "-autoexit", "-loglevel", "quiet", streamURL})
	default:
		return p.startSimpleLocked([]string{"--intf", "dummy", "--play-and-exit", streamURL})
	}
}

func (p *Player) startMPVLocked() error {
	p.ipcPath = filepath.Join(os.TempDir(), fmt.Sprintf("radioko-leka-%d.sock", os.Getpid()))
	_ = os.Remove(p.ipcPath)
	p.cmd = exec.Command(p.engine, "--idle=yes", "--no-video", "--really-quiet", "--input-ipc-server="+p.ipcPath)
	if err := p.cmd.Start(); err != nil {
		p.cmd = nil
		p.ipcPath = ""
		return fmt.Errorf("démarrage du lecteur: %w", err)
	}
	p.watchLocked()
	for attempt := 0; attempt < 50; attempt++ {
		if _, err := os.Stat(p.ipcPath); err == nil {
			return nil
		}
		time.Sleep(20 * time.Millisecond)
	}
	p.stopLocked()
	return fmt.Errorf("mpv n'a pas ouvert son socket de contrôle")
}

func (p *Player) startSimpleLocked(args []string) error {
	p.stopLocked()
	p.cmd = exec.Command(p.engine, args...)
	if err := p.cmd.Start(); err != nil {
		p.cmd = nil
		return fmt.Errorf("démarrage du lecteur: %w", err)
	}
	p.streaming = true
	p.watchLocked()
	return nil
}

func (p *Player) watchLocked() {
	cmd := p.cmd
	go func() {
		_ = cmd.Wait()
		p.mu.Lock()
		if p.cmd == cmd {
			p.cmd = nil
			if p.ipcPath != "" {
				_ = os.Remove(p.ipcPath)
				p.ipcPath = ""
			}
			p.streaming = false
		}
		p.mu.Unlock()
	}()
}

func (p *Player) sendLocked(command ...any) error {
	if p.ipcPath == "" {
		return fmt.Errorf("le contrôle interactif nécessite mpv")
	}
	connection, err := net.DialTimeout("unix", p.ipcPath, time.Second)
	if err != nil {
		return fmt.Errorf("connexion à mpv: %w", err)
	}
	defer connection.Close()
	payload, err := json.Marshal(map[string]any{"command": command})
	if err != nil {
		return fmt.Errorf("encodage de la commande mpv: %w", err)
	}
	if _, err := connection.Write(append(payload, '\n')); err != nil {
		return fmt.Errorf("commande mpv: %w", err)
	}
	return nil
}

func (p *Player) TogglePause() (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.streaming {
		return false, fmt.Errorf("aucune station en cours")
	}
	if err := p.sendLocked("cycle", "pause"); err != nil {
		return p.paused, err
	}
	p.paused = !p.paused
	return p.paused, nil
}

func (p *Player) ToggleMute() (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.streaming {
		return false, fmt.Errorf("aucune station en cours")
	}
	if err := p.sendLocked("cycle", "mute"); err != nil {
		return p.muted, err
	}
	p.muted = !p.muted
	return p.muted, nil
}

func (p *Player) ChangeVolume(delta int) (int, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.volume = clamp(p.volume+delta, 0, 100)
	if p.streaming {
		if err := p.sendLocked("set_property", "volume", p.volume); err != nil {
			return p.volume, err
		}
	}
	return p.volume, nil
}

func (p *Player) Status() (volume int, paused, muted bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.volume, p.paused, p.muted
}

func clamp(value, min, max int) int {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}

func filepathBase(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == '/' || path[i] == '\\' {
			return path[i+1:]
		}
	}
	return path
}

func (p *Player) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.stopLocked()
}

func (p *Player) stopLocked() {
	if p.cmd != nil && p.cmd.Process != nil {
		_ = p.cmd.Process.Kill()
		p.cmd = nil
	}
	if p.ipcPath != "" {
		_ = os.Remove(p.ipcPath)
		p.ipcPath = ""
	}
	p.streaming = false
	p.paused = false
	p.muted = false
}
