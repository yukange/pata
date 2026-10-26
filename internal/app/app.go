package app

import (
	"embed"
	"net/http"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

func setupApplicationMenu(app *application.App, mainWindow *application.WebviewWindow, updaterSvc *UpdaterService) *application.Menu {
	menu := application.NewMenu()

	if runtime.GOOS == "darwin" {
		pataMenu := menu.AddSubmenu("Pata")
		pataMenu.AddRole(application.About)
		pataMenu.AddSeparator()

		settingsItem := pataMenu.Add("设置…").SetAccelerator("CmdOrCtrl+,")
		settingsItem.OnClick(func(ctx *application.Context) {
			if mainWindow.IsMinimised() {
				mainWindow.UnMinimise()
			}
			mainWindow.Show()
			mainWindow.Focus()
			app.Event.Emit("menu:open-settings")
		})

		checkUpdatesItem := pataMenu.Add("检查更新…")
		checkUpdatesItem.OnClick(func(ctx *application.Context) {
			if mainWindow.IsMinimised() {
				mainWindow.UnMinimise()
			}
			mainWindow.Show()
			mainWindow.Focus()
			updaterSvc.triggerManualCheckFromMenu()
		})

		pataMenu.AddSeparator()
		pataMenu.AddRole(application.ServicesMenu)
		pataMenu.AddSeparator()
		pataMenu.AddRole(application.Hide)
		pataMenu.AddRole(application.HideOthers)
		pataMenu.AddRole(application.UnHide)
		pataMenu.AddSeparator()
		pataMenu.AddRole(application.Quit)
	} else {
		menu.AddRole(application.AppMenu)
	}

	menu.AddRole(application.FileMenu)
	menu.AddRole(application.EditMenu)
	menu.AddRole(application.ViewMenu)
	menu.AddRole(application.WindowMenu)
	menu.AddRole(application.HelpMenu)

	return menu
}

// Run creates and starts the desktop application.
func Run(assets embed.FS, trayIcon []byte, version string, officialBuild bool) error {
	vaultService := NewVaultService()
	mcpService := newMCPService(vaultService)
	updaterService := NewUpdaterService(vaultService, version, officialBuild)

	app := application.New(application.Options{
		Name:        "Pata",
		Description: "Personal task and note workspace",
		Services: []application.Service{
			application.NewService(vaultService),
			application.NewService(mcpService),
			application.NewService(updaterService),
		},
		Assets: application.AssetOptions{
			Handler: application.AssetFileServerFS(assets),
			Middleware: func(next http.Handler) http.Handler {
				return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if strings.HasPrefix(r.URL.Path, "/vault-audio/") {
						relPath := strings.TrimPrefix(r.URL.Path, "/vault-audio/")
						absPath, err := vaultService.resolveSafeFilePath(relPath)
						if err != nil {
							http.NotFound(w, r)
							return
						}
						http.ServeFile(w, r, absPath)
						return
					}
					next.ServeHTTP(w, r)
				})
			},
		},
		Mac: application.MacOptions{
			ApplicationShouldTerminateAfterLastWindowClosed: true,
		},
	})

	savedWindow, _ := vaultService.GetWindowStatePreference()
	winWidth, winHeight := OpenWindowSize(savedWindow)
	startState := application.WindowStateNormal
	if savedWindow != nil && savedWindow.IsMaximised {
		startState = application.WindowStateMaximised
	}

	// Create window with MacTitleBarHiddenInset according to macos-native spec
	mainWindow := app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title:      "Pata",
		Width:      winWidth,
		Height:     winHeight,
		MinWidth:   MinWindowWidth,
		MinHeight:  MinWindowHeight,
		StartState: startState,
		Mac: application.MacWindow{
			Backdrop: application.MacBackdropTranslucent,
			TitleBar: application.MacTitleBarHiddenInset,
		},
		BackgroundColour: application.NewRGB(250, 250, 248),
		URL:              "/",
	})

	tracker := newWindowStateTracker(mainWindow, vaultService)
	tracker.attach(app)

	// Configure macOS standard application menu
	appMenu := setupApplicationMenu(app, mainWindow, updaterService)
	app.Menu.SetApplicationMenu(appMenu)

	// Initialize updater with app
	_ = updaterService.initUpdater(app)

	// Configure static system tray
	tray := app.SystemTray.New()
	tray.SetTemplateIcon(trayIcon)
	tray.SetTooltip("Pata")
	tray.OnClick(func() {
		if mainWindow.IsMinimised() {
			mainWindow.UnMinimise()
		}
		mainWindow.Show()
		mainWindow.Focus()
	})

	return app.Run()
}

type windowStateTracker struct {
	window       *application.WebviewWindow
	vaultService *VaultService
	mu           sync.Mutex
	timer        *time.Timer
}

func newWindowStateTracker(window *application.WebviewWindow, vaultService *VaultService) *windowStateTracker {
	return &windowStateTracker{
		window:       window,
		vaultService: vaultService,
	}
}

func (t *windowStateTracker) scheduleSave(delay time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.timer != nil {
		t.timer.Stop()
	}
	t.timer = time.AfterFunc(delay, t.saveNow)
}

func (t *windowStateTracker) saveNow() {
	t.mu.Lock()
	if t.timer != nil {
		t.timer.Stop()
		t.timer = nil
	}
	t.mu.Unlock()

	if t.window == nil {
		return
	}
	// Do not save when fullscreen or minimised
	if t.window.IsFullscreen() || t.window.IsMinimised() {
		return
	}
	w, h := t.window.Size()
	if w < MinWindowWidth || h < MinWindowHeight {
		return
	}
	isMax := t.window.IsMaximised()
	_ = t.vaultService.UpdateWindowState(w, h, isMax)
}

func (t *windowStateTracker) attach(app *application.App) {
	t.window.OnWindowEvent(events.Common.WindowDidResize, func(*application.WindowEvent) {
		t.scheduleSave(400 * time.Millisecond)
	})
	t.window.OnWindowEvent(events.Common.WindowMaximise, func(*application.WindowEvent) {
		t.scheduleSave(200 * time.Millisecond)
	})
	t.window.OnWindowEvent(events.Common.WindowUnMaximise, func(*application.WindowEvent) {
		t.scheduleSave(200 * time.Millisecond)
	})
	t.window.OnWindowEvent(events.Common.WindowClosing, func(*application.WindowEvent) {
		t.saveNow()
	})
	app.OnShutdown(func() {
		t.saveNow()
	})
}
