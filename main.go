package main

import (
	"embed"
	"fmt"
	"log"
	"os"

	"pata/internal/app"
)

var (
	// Version is the current application version (SemVer, e.g. "0.1.1").
	// Can be injected at build time via -ldflags "-X main.Version=x.y.z".
	Version = "0.1.1"

	// OfficialBuild indicates whether this binary is an official release distribution.
	// Can be injected at build time via -ldflags "-X main.OfficialBuild=true".
	OfficialBuild = "false"
)

//go:embed all:frontend/dist
var assets embed.FS

//go:embed assets/branding/tray/tray.png
var trayIcon []byte

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v" || os.Args[1] == "version") {
		fmt.Printf("Pata %s (official_build: %s)\n", Version, OfficialBuild)
		return
	}

	if err := app.Run(assets, trayIcon, Version, OfficialBuild == "true"); err != nil {
		log.Fatal(err)
	}
}
