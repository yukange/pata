package main

import (
	"embed"
	"log"
	"net/http"
	"strings"

	"github.com/wailsapp/wails/v3/pkg/application"
)

//go:embed all:frontend/dist
var assets embed.FS

//go:embed assets/branding/tray/tray.png
var trayIcon []byte

func main() {
	vaultService := NewVaultService()

	app := application.New(application.Options{
		Name:        "Pata",
		Description: "Personal task and note workspace",
		Services: []application.Service{
			application.NewService(vaultService),
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

	// Configure macOS standard application menu
	appMenu := application.DefaultApplicationMenu()
	app.Menu.SetApplicationMenu(appMenu)

	// Create window with MacTitleBarHiddenInset according to macos-native spec
	mainWindow := app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title:     "Pata",
		Width:     1120,
		Height:    740,
		MinWidth:  800,
		MinHeight: 520,
		Mac: application.MacWindow{
			Backdrop: application.MacBackdropTranslucent,
			TitleBar: application.MacTitleBarHiddenInset,
		},
		BackgroundColour: application.NewRGB(250, 250, 248),
		URL:              "/",
	})

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

	err := app.Run()
	if err != nil {
		log.Fatal(err)
	}
}
