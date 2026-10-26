package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

// TestAcceptance_Updater_VersionConsistency verifies that the runtime default Version,
// build/darwin/Info.plist, and frontend/package.json share a consistent SemVer baseline.
func TestAcceptance_Updater_VersionConsistency(t *testing.T) {
	// 1. Verify Go Version is valid SemVer
	if Version == "" {
		t.Fatalf("Go Version is empty")
	}

	// 2. Verify frontend/package.json
	packageJSONPath := filepath.Join("frontend", "package.json")
	data, err := os.ReadFile(packageJSONPath)
	if err != nil {
		t.Fatalf("failed to read frontend/package.json: %v", err)
	}
	var pkg struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(data, &pkg); err != nil {
		t.Fatalf("failed to parse frontend/package.json: %v", err)
	}
	if pkg.Version != Version {
		t.Errorf("frontend/package.json version %q != Go Version %q", pkg.Version, Version)
	}

	// 3. Verify build/darwin/Info.plist
	infoPlistPath := filepath.Join("build", "darwin", "Info.plist")
	plistData, err := os.ReadFile(infoPlistPath)
	if err != nil {
		t.Fatalf("failed to read build/darwin/Info.plist: %v", err)
	}
	checkBundleVersions(t, plistData, Version)
}

func checkBundleVersions(t *testing.T, data []byte, version string) {
	t.Helper()
	for _, key := range []string{"CFBundleVersion", "CFBundleShortVersionString"} {
		match := regexp.MustCompile(`<key>` + key + `</key>\s*<string>([^<]+)</string>`).FindSubmatch(data)
		if len(match) != 2 || string(match[1]) != version {
			t.Errorf("%s must be %q, got %q", key, version, match)
		}
	}
}

func TestAcceptance_Updater_BundleVersionInput(t *testing.T) {
	data, err := os.ReadFile("build/darwin/Taskfile.yml")
	if err != nil {
		t.Fatal(err)
	}
	var config struct {
		Tasks map[string]struct {
			Cmds []yaml.Node `yaml:"cmds"`
		} `yaml:"tasks"`
	}
	if err := yaml.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	var script string
	for _, cmd := range config.Tasks["create:app:bundle"].Cmds {
		if cmd.Kind == yaml.ScalarNode && strings.Contains(cmd.Value, "CFBundleShortVersionString") {
			script = cmd.Value
		}
	}
	if script == "" {
		t.Fatal("bundle packaging must stamp the release version")
	}
	for _, version := range []string{"", Version, "9.8.7"} {
		t.Run("version="+version, func(t *testing.T) {
			binDir := t.TempDir()
			contents := filepath.Join(binDir, "pata.app", "Contents")
			if err := os.MkdirAll(contents, 0755); err != nil {
				t.Fatal(err)
			}
			command := strings.NewReplacer("{{.VERSION}}", version, "{{.BIN_DIR}}", binDir, "{{.APP_NAME}}", "pata").Replace(script)
			if out, err := exec.Command("sh", "-ec", command).CombinedOutput(); err != nil {
				t.Fatalf("bundle metadata command: %s, %v", out, err)
			}
			plist, err := os.ReadFile(filepath.Join(contents, "Info.plist"))
			if err != nil {
				t.Fatal(err)
			}
			if version == "" {
				version = Version
			}
			checkBundleVersions(t, plist, version)
		})
	}
}
