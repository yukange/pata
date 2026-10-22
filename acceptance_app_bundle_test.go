package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// TestAcceptance_AppBundle_CompliesWithMacOSPackagingAndCodeSign validates the macOS application
// package on the real machine: binary executable, deep codesign verification, Info.plist bundle ID,
// icons.icns, and embedded frontend assets.
func TestAcceptance_AppBundle_CompliesWithMacOSPackagingAndCodeSign(t *testing.T) {
	appPath := filepath.Join("bin", "pata.app")
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		t.Fatalf("bin/pata.app does not exist. Please run packaging first.")
	}

	// 1. Verify executable exists and codesign passes
	execPath := filepath.Join(appPath, "Contents", "MacOS", "pata")
	fi, err := os.Stat(execPath)
	if err != nil || fi.Size() == 0 {
		t.Fatalf("Contents/MacOS/pata executable missing or empty: %v", err)
	}

	cmd := exec.Command("codesign", "--verify", "--deep", "--strict", appPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("codesign verification failed: %s, err: %v", string(out), err)
	}

	// 2. Verify Info.plist contains valid bundle identifier
	plistPath := filepath.Join(appPath, "Contents", "Info.plist")
	plistData, err := os.ReadFile(plistPath)
	if err != nil {
		t.Fatalf("failed to read Info.plist: %v", err)
	}
	if !strings.Contains(string(plistData), "<string>com.pata.app</string>") {
		t.Fatalf("Info.plist missing expected CFBundleIdentifier 'com.pata.app'")
	}

	// 3. Verify icons.icns exists and is non-empty
	icnsPath := filepath.Join(appPath, "Contents", "Resources", "icons.icns")
	icnsInfo, err := os.Stat(icnsPath)
	if err != nil || icnsInfo.Size() < 100000 {
		t.Fatalf("icons.icns missing or unexpectedly small: %v", err)
	}

	// 4. Verify embedded frontend assets inside production binary
	if assetsFile, err := assets.Open("frontend/dist/index.html"); err != nil {
		t.Fatalf("embedded assets missing frontend/dist/index.html: %v", err)
	} else {
		_ = assetsFile.Close()
	}
}

// TestAcceptance_AppBundle_BrandingIconsAndResources verifies macOS branding integrity:
// icons.icns unpacks cleanly into standard resolutions, Assets.car is absent (avoiding Wails defaults),
// and tray icon is present.
func TestAcceptance_AppBundle_BrandingIconsAndResources(t *testing.T) {
	appPath := filepath.Join("bin", "pata.app")
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		t.Fatalf("bin/pata.app does not exist. Run 'wails3 task package' first.")
	}

	resDir := filepath.Join(appPath, "Contents", "Resources")
	icnsPath := filepath.Join(resDir, "icons.icns")

	assetsCarPath := filepath.Join(resDir, "Assets.car")
	if _, err := os.Stat(assetsCarPath); !os.IsNotExist(err) {
		t.Fatalf("Assets.car should NOT exist in pata.app (must prevent Wails default icon residue)")
	}

	// Verify icons.icns unpacks cleanly with iconutil
	tmpIconset, err := os.MkdirTemp("", "pata-iconset-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpIconset)

	iconsetTarget := filepath.Join(tmpIconset, "check.iconset")
	unpackCmd := exec.Command("iconutil", "-c", "iconset", icnsPath, "-o", iconsetTarget)
	if out, err := unpackCmd.CombinedOutput(); err != nil {
		t.Fatalf("iconutil unpack failed: %s, err: %v", string(out), err)
	}

	expectedSizes := []string{
		"icon_16x16@2x.png",
		"icon_32x32@2x.png",
		"icon_128x128.png",
		"icon_128x128@2x.png",
		"icon_256x256.png",
		"icon_256x256@2x.png",
		"icon_512x512.png",
		"icon_512x512@2x.png",
	}
	for _, expected := range expectedSizes {
		p := filepath.Join(iconsetTarget, expected)
		if fi, err := os.Stat(p); err != nil || fi.Size() == 0 {
			t.Errorf("missing or empty icon variant: %s", expected)
		}
	}

	trayPath := filepath.Join("assets", "branding", "tray", "tray.png")
	if fi, err := os.Stat(trayPath); err != nil || fi.Size() == 0 {
		t.Fatalf("tray.png missing or empty: %v", err)
	}
}

// TestAcceptance_AppBundle_LiveProcessLaunch verifies that bin/pata.app launches successfully
// as a macOS process, registers with the OS kernel, and gracefully handles termination.
func TestAcceptance_AppBundle_LiveProcessLaunch(t *testing.T) {
	appPath := filepath.Join("bin", "pata.app")
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		t.Skip("skipping live process test: bin/pata.app not found")
	}

	launchCmd := exec.Command(filepath.Join(appPath, "Contents", "MacOS", "pata"))
	if err := launchCmd.Start(); err != nil {
		t.Fatalf("failed to launch bin/pata.app: %v", err)
	}
	defer func() {
		if launchCmd.Process != nil {
			_ = launchCmd.Process.Kill()
		}
	}()

	// Wait 1.5s to ensure window/app process initializes
	time.Sleep(1500 * time.Millisecond)

	// Check that process is running in macOS kernel
	if err := launchCmd.Process.Signal(os.Signal(syscall.Signal(0))); err != nil {
		t.Fatalf("pata process died prematurely: %v", err)
	}

	// Gracefully terminate the launched instance
	_ = launchCmd.Process.Signal(os.Interrupt)
	_ = launchCmd.Wait()
}
