package app

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/wailsapp/wails/v3/pkg/application"
	"pata/internal/storage/markdown"
)

const mcpListenAddress = "127.0.0.1:17373"

type MCPStatus struct {
	Enabled      bool   `json:"enabled"`
	Running      bool   `json:"running"`
	Endpoint     string `json:"endpoint"`
	VaultChanged bool   `json:"vaultChanged"`
	Error        string `json:"error"`
}

type MCPService struct {
	mu      sync.Mutex
	vault   *VaultService
	runtime *mcpRuntime
	err     string
	enabled bool
}

type mcpRuntime struct {
	gate     sync.RWMutex
	active   bool
	vault    *markdown.Vault
	http     *http.Server
	listener net.Listener
}

func newMCPService(vault *VaultService) *MCPService {
	return &MCPService{vault: vault}
}

func (s *MCPService) ServiceStartup(ctx context.Context, options application.ServiceOptions) error {
	s.vault.mu.Lock()
	cfg, err := s.vault.loadConfig()
	s.vault.mu.Unlock()
	s.mu.Lock()
	s.enabled = cfg.MCPEnabled
	if err != nil {
		s.err = "无法读取 MCP 启用设置，请检查应用配置"
	}
	s.mu.Unlock()
	if err == nil && cfg.MCPEnabled {
		if _, err := s.Start(); err != nil {
			s.mu.Lock()
			s.err = "MCP 自动启动失败：" + err.Error()
			s.mu.Unlock()
		}
	}
	return nil
}

func (s *MCPService) saveEnabled(enabled bool) error {
	s.vault.mu.Lock()
	defer s.vault.mu.Unlock()
	cfg, err := s.vault.loadConfig()
	if err != nil {
		return fmt.Errorf("无法读取 MCP 启用设置")
	}
	cfg.MCPEnabled = enabled
	if err := s.vault.saveConfig(cfg); err != nil {
		return fmt.Errorf("无法保存 MCP 启用设置，请检查应用配置目录权限")
	}
	s.enabled = enabled
	return nil
}

func (s *MCPService) GetStatus() MCPStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.statusLocked()
}

func (s *MCPService) statusLocked() MCPStatus {
	status := MCPStatus{Error: s.err, Enabled: s.enabled}
	if s.runtime != nil {
		status.Running = true
		status.Endpoint = "http://" + mcpListenAddress + "/mcp"
		s.vault.mu.Lock()
		status.VaultChanged = s.vault.vault != s.runtime.vault
		s.vault.mu.Unlock()
	}
	return status
}

func (s *MCPService) Start() (MCPStatus, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.runtime != nil {
		return s.statusLocked(), nil
	}
	s.vault.externalMu.RLock()
	defer s.vault.externalMu.RUnlock()
	s.vault.mu.Lock()
	vault := s.vault.vault
	s.vault.mu.Unlock()
	if vault == nil {
		return s.statusLocked(), fmt.Errorf("请先选择并打开资料库")
	}
	listener, err := net.Listen("tcp4", mcpListenAddress)
	if err != nil {
		return s.statusLocked(), fmt.Errorf("无法启动 MCP：本机端口 17373 不可用，请关闭占用此端口的程序后重试")
	}
	if !s.enabled {
		if err := s.saveEnabled(true); err != nil {
			_ = listener.Close()
			return s.statusLocked(), err
		}
	}

	rt := &mcpRuntime{active: true, vault: vault, listener: listener}
	server := newPataMCPServer(s.vault, rt)
	handler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return server }, &mcp.StreamableHTTPOptions{
		Stateless: true, JSONResponse: true,
	})
	rt.http = &http.Server{
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 << 10,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Host != mcpListenAddress || len(r.Header.Values("Origin")) != 0 {
				http.Error(w, "Forbidden", http.StatusForbidden)
				return
			}
			if r.URL.Path != "/mcp" {
				http.NotFound(w, r)
				return
			}
			r.Body = http.MaxBytesReader(w, r.Body, 4<<20)
			handler.ServeHTTP(w, r)
		}),
	}
	s.runtime, s.err = rt, ""
	go func() {
		err := rt.http.Serve(listener)
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.runtime == rt {
			rt.stop()
			s.runtime = nil
			if err != nil && err != http.ErrServerClosed {
				s.err = "MCP 服务已停止，请重新启动"
			}
		}
	}()
	return s.statusLocked(), nil
}

func (s *MCPService) Stop() (MCPStatus, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.runtime != nil {
		s.runtime.stop()
		s.runtime = nil
	}
	s.enabled = false
	s.err = ""
	if err := s.saveEnabled(false); err != nil {
		s.err = "MCP 服务已停止，但关闭状态未保存。下次打开 Pata 时可能自动启动。" + err.Error()
	}
	return s.statusLocked(), nil
}

func (rt *mcpRuntime) stop() {
	rt.gate.Lock()
	rt.active = false
	rt.gate.Unlock()
	_ = rt.listener.Close()
	_ = rt.http.Close()
}

func (s *MCPService) ServiceShutdown() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.runtime != nil {
		s.runtime.stop()
		s.runtime = nil
	}
	return nil
}

func mcpScope(ctx context.Context, service *VaultService, rt *mcpRuntime, call func() (any, error)) (any, error) {
	rt.gate.RLock()
	defer rt.gate.RUnlock()
	if !rt.active {
		return nil, fmt.Errorf("MCP 服务已停止")
	}
	service.externalMu.RLock()
	defer service.externalMu.RUnlock()
	service.mu.Lock()
	current := service.vault
	service.mu.Unlock()
	if current != rt.vault {
		return nil, fmt.Errorf("资料库已更换，请在 Pata 设置中停止并重新启动 MCP 服务")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return call()
}
