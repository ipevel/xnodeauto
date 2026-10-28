// sync-nodes —— Xboard 节点自动同步
//
// 从面板拉取节点列表，为每台节点生成 xboard-node 实例配置并管理 systemd
// 实例（xboard-node@<id>.service）。行为与被替换的旧二进制保持一致：
//   - 手动模式：sync.yml 里给了 manual_node_ids 就只跑这些
//   - 自动模式：按本机 IP 与节点 host 匹配；命中 >=2 个时拒绝执行（中转/CDN 场景）
//   - 配置有变化才重启实例；新增节点自动 start；面板里消失的节点 stop 并删配置
//
// 相对旧版的唯一行为变更：写出的实例配置额外带 kernel 段。
// 旧版只写 panel 三段，导致 xboard-node 落到默认 sing-box 内核，
// 而 sing-box 不支持 xhttp / VLESS Encryption。现在默认写 xray，
// 也可以在 sync.yml 用 kernel_type 指定。
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	defaultConfigPath = "/etc/xboard-node/sync.yml"
	defaultNodeDir    = "/etc/xboard-node"
	unitFmt           = "xboard-node@%d.service"
	unitGlob          = "xboard-node@*.service"
	httpTO            = 20 * time.Second
	version           = "1.3.1"
)

var (
	configPath = defaultConfigPath
	nodeDir    = defaultNodeDir
	dryRun     = false
)

// ---------- 配置 ----------

type SyncConfig struct {
	XboardURL     string `yaml:"xboard_url"`
	AdminPath     string `yaml:"admin_path"`
	AdminEmail    string `yaml:"admin_email"`
	AdminPassword string `yaml:"admin_password"`
	PanelToken    string `yaml:"panel_token"`
	ManualNodeIDs []int  `yaml:"manual_node_ids"`

	// 新增：内核与证书相关（旧版写死 sing-box 默认，无法表达）
	KernelType     string `yaml:"kernel_type"`      // xray | singbox，默认 xray
	KernelLogLevel string `yaml:"kernel_log_level"` // 默认 warn
	ConfigDir      string `yaml:"config_dir"`       // 默认 /etc/xboard-node
	CertMode       string `yaml:"cert_mode"`        // 可选，写入 cert 段

	// 按节点覆盖内核：node_id -> xray|singbox。
	// 用于同机混跑不同协议的节点（如 xhttp 需要 xray、tuic 需要 sing-box）。
	NodeKernelTypes map[int]string `yaml:"node_kernel_types"`
}

// 实例配置文件结构：panel + kernel (+ cert)
type nodeConfig struct {
	Panel  panelConfig  `yaml:"panel"`
	Kernel kernelConfig `yaml:"kernel,omitempty"`
	Cert   *certConfig  `yaml:"cert,omitempty"`
}

type panelConfig struct {
	URL    string `yaml:"url"`
	Token  string `yaml:"token"`
	NodeID int    `yaml:"node_id"`
}

type kernelConfig struct {
	Type      string `yaml:"type"`
	ConfigDir string `yaml:"config_dir,omitempty"`
	LogLevel  string `yaml:"log_level,omitempty"`
}

type certConfig struct {
	CertMode string `yaml:"cert_mode"`
}

// ---------- 面板 API ----------

type apiClient struct {
	base  string
	token string
	http  *http.Client
}

type loginResponse struct {
	Data struct {
		Token string `json:"token"`
		Auth  string `json:"auth_data"`
	} `json:"data"`
}

type panelNode struct {
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Host    string `json:"host"`
	Port    any    `json:"port"`
	Type    string `json:"type"`
	Enabled any    `json:"enabled"`
}

type nodesResponse struct {
	Data []panelNode `json:"data"`
}

func newAPIClient(base, token string) *apiClient {
	return &apiClient{
		base:  strings.TrimRight(base, "/"),
		token: token,
		http:  &http.Client{Timeout: httpTO},
	}
}

func (c *apiClient) login(email, password string) (string, error) {
	body, _ := json.Marshal(map[string]string{"email": email, "password": password})
	req, err := http.NewRequest(http.MethodPost, c.base+"/api/v2/passport/auth/login", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("login request: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login failed (status %d): %s", resp.StatusCode, string(raw))
	}
	var lr loginResponse
	if err := json.Unmarshal(raw, &lr); err != nil {
		return "", fmt.Errorf("parse login response: %w", err)
	}
	tok := lr.Data.Auth
	if tok == "" {
		tok = lr.Data.Token
	}
	if tok == "" {
		return "", fmt.Errorf("login response has no token")
	}
	return tok, nil
}

func (c *apiClient) fetchNodes(adminPath string) ([]panelNode, error) {
	url := fmt.Sprintf("%s/api/v2/%s/server/manage/getNodes", c.base, adminPath)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch nodes: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch nodes failed (status %d): %s", resp.StatusCode, string(raw))
	}
	var nr nodesResponse
	if err := json.Unmarshal(raw, &nr); err != nil {
		return nil, fmt.Errorf("parse nodes response: %w", err)
	}
	return nr.Data, nil
}

// ---------- 本机 IP ----------

func getMyIPs() []string {
	ips := map[string]bool{}
	add := func(ip string) {
		ip = strings.TrimSpace(ip)
		if ip == "" {
			return
		}
		ips[ip] = true
		if strings.HasPrefix(ip, "::ffff:") {
			ips[strings.TrimPrefix(ip, "::ffff:")] = true
		}
	}

	// 本地网卡
	if ifaces, err := net.Interfaces(); err == nil {
		for _, ifc := range ifaces {
			addrs, err := ifc.Addrs()
			if err != nil {
				continue
			}
			for _, a := range addrs {
				if ipnet, ok := a.(*net.IPNet); ok {
					add(ipnet.IP.String())
				}
			}
		}
	}

	// 公网 IP
	if resp, err := (&http.Client{Timeout: 8 * time.Second}).Get("https://api.ipify.org"); err == nil {
		defer resp.Body.Close()
		if b, err := io.ReadAll(resp.Body); err == nil {
			add(string(b))
		}
	}

	out := make([]string, 0, len(ips))
	for ip := range ips {
		out = append(out, ip)
	}
	return out
}

func hostToIP(host string) []string {
	if ip := net.ParseIP(host); ip != nil {
		s := ip.String()
		if strings.HasPrefix(s, "::ffff:") {
			return []string{s, strings.TrimPrefix(s, "::ffff:")}
		}
		return []string{s}
	}
	addrs, err := net.LookupHost(host)
	if err != nil {
		return nil
	}
	return addrs
}

// ---------- systemd ----------

func systemctl(args ...string) (string, error) {
	if dryRun {
		logInfo("[dry-run] systemctl %s", strings.Join(args, " "))
		return "", nil
	}
	cmd := exec.Command("systemctl", args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	return strings.TrimSpace(buf.String()), err
}

var unitRe = regexp.MustCompile(`xboard-node@(\d+)\.service`)

func runningInstances() map[int]bool {
	out := map[int]bool{}
	units, _ := systemctl("list-units", unitGlob, "--all", "--no-legend", "--no-pager")
	for _, line := range strings.Split(units, "\n") {
		m := unitRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		id, _ := strconv.Atoi(m[1])
		fields := strings.Fields(line)
		active := false
		for _, f := range fields {
			if f == "active" {
				active = true
			}
		}
		if active {
			out[id] = true
		}
	}
	return out
}

func waitForNode(id int, timeout time.Duration) error {
	if dryRun {
		return nil
	}
	deadline := time.Now().Add(timeout)
	unit := fmt.Sprintf(unitFmt, id)
	for time.Now().Before(deadline) {
		out, _ := systemctl("is-active", unit)
		if strings.TrimSpace(out) == "active" {
			return nil
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("node %d not active after %s", id, timeout)
}

// ---------- 配置读写 ----------

func loadConfig(path string) (*SyncConfig, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var cfg SyncConfig
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	if cfg.KernelType == "" {
		cfg.KernelType = "xray" // 默认 xray：sing-box 不支持 xhttp / VLESS Encryption
	}
	if cfg.KernelLogLevel == "" {
		cfg.KernelLogLevel = "warn"
	}
	if cfg.ConfigDir == "" {
		cfg.ConfigDir = nodeDir
	}
	return &cfg, nil
}

func buildNodeConfig(cfg *SyncConfig, nodeID int) nodeConfig {
	// 按节点覆盖内核（node_kernel_types），未配置时用全局 kernel_type
	kernelType := cfg.KernelType
	if kt, ok := cfg.NodeKernelTypes[nodeID]; ok && kt != "" {
		kernelType = kt
	}
	nc := nodeConfig{
		Panel: panelConfig{
			URL:    cfg.XboardURL,
			Token:  cfg.PanelToken,
			NodeID: nodeID,
		},
		Kernel: kernelConfig{
			Type:      kernelType,
			ConfigDir: cfg.ConfigDir,
			LogLevel:  cfg.KernelLogLevel,
		},
	}
	if cfg.CertMode != "" {
		nc.Cert = &certConfig{CertMode: cfg.CertMode}
	}
	return nc
}

func writeConfig(path string, nc nodeConfig) (bool, error) {
	out, err := yaml.Marshal(nc)
	if err != nil {
		return false, fmt.Errorf("marshal: %w", err)
	}
	old, err := os.ReadFile(path)
	if err == nil && bytes.Equal(old, out) {
		return false, nil // 无变化
	}
	if dryRun {
		logInfo("[dry-run] would write %s:", path)
		fmt.Println(strings.TrimRight(string(out), "\n"))
		return true, nil
	}
	if err := os.WriteFile(path, out, 0o644); err != nil {
		return false, fmt.Errorf("write %s: %w", path, err)
	}
	return true, nil
}

// ---------- 日志 ----------

func stamp() string { return time.Now().Format("2006-01-02 15:04:05") }

func logInfo(f string, a ...any)  { fmt.Printf("[%s] [INFO] %s\n", stamp(), fmt.Sprintf(f, a...)) }
func logWarn(f string, a ...any)  { fmt.Printf("[%s] [WARN] %s\n", stamp(), fmt.Sprintf(f, a...)) }
func logError(f string, a ...any) { fmt.Printf("[%s] [ERROR] %s\n", stamp(), fmt.Sprintf(f, a...)) }

// ---------- 主流程 ----------

func main() {
	start := time.Now()

	// 便于测试/自定义路径：
	//   --config <path>  指定 sync.yml
	//   --node-dir <dir> 指定节点配置目录
	//   --dry-run        只打印将要做的动作，不写文件、不动 systemd
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--config":
			if i+1 < len(args) {
				configPath = args[i+1]
				i++
			}
		case "--node-dir":
			if i+1 < len(args) {
				nodeDir = args[i+1]
				i++
			}
		case "--dry-run":
			dryRun = true
		case "-v", "--version":
			fmt.Printf("sync-nodes version %s\n", version)
			return
		case "-h", "--help":
			fmt.Printf("sync-nodes %s\n\n  --config <path>\n  --node-dir <dir>\n  --dry-run\n  -v\n", version)
			return
		}
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		logError("%v", err)
		os.Exit(1)
	}

	api := newAPIClient(cfg.XboardURL, "")
	if cfg.AdminEmail != "" && cfg.AdminPassword != "" {
		tok, err := api.login(cfg.AdminEmail, cfg.AdminPassword)
		if err != nil {
			logError("%v", err)
			os.Exit(1)
		}
		api.token = tok
	}
	if api.token == "" {
		api.token = cfg.PanelToken
	}

	nodes, err := api.fetchNodes(cfg.AdminPath)
	if err != nil {
		logError("%v", err)
		os.Exit(1)
	}
	logInfo("fetched %d nodes from panel", len(nodes))

	byID := map[int]panelNode{}
	for _, n := range nodes {
		byID[n.ID] = n
	}

	// 决定要跑哪些节点
	var want []int
	if len(cfg.ManualNodeIDs) > 0 {
		logInfo("using manual node IDs: %v", cfg.ManualNodeIDs)
		for _, id := range cfg.ManualNodeIDs {
			if _, ok := byID[id]; !ok {
				logWarn("node %d not found in panel", id)
				continue
			}
			want = append(want, id)
		}
	} else {
		// 自动模式：按本机 IP 匹配节点 host
		myIPs := getMyIPs()
		logInfo("detected IPs: %v", myIPs)
		last := map[string]bool{}
		for _, ip := range myIPs {
			last[ip] = true
		}
		var matched []int
		for _, n := range nodes {
			for _, ip := range hostToIP(n.Host) {
				if last[ip] {
					logInfo("node %d (%s) matched: %s -> %s", n.ID, n.Name, n.Host, ip)
					matched = append(matched, n.ID)
					break
				}
			}
		}
		if len(matched) >= 2 {
			logError("auto-detection is disabled for safety, please use manual mode instead")
			logError("detected %d nodes matching this server (potential relay/CDN scenario)", len(matched))
			fmt.Fprintf(os.Stderr, "\nAdd 'manual_node_ids' to your config:\n  manual_node_ids:\n")
			for _, id := range matched {
				fmt.Fprintf(os.Stderr, "    - %d\n", id)
			}
			os.Exit(1)
		}
		want = matched
	}

	running := runningInstances()
	logInfo("current running: %d nodes, should run: %d nodes", len(running), len(want))

	wantSet := map[int]bool{}
	for _, id := range want {
		wantSet[id] = true
	}

	changed := false

	// 新增或配置变化
	for _, id := range want {
		path := filepath.Join(cfg.ConfigDir, fmt.Sprintf("%d.yml", id))
		dirty, err := writeConfig(path, buildNodeConfig(cfg, id))
		if err != nil {
			logError("write config for node %d failed: %v", id, err)
			continue
		}
		unit := fmt.Sprintf(unitFmt, id)
		if !running[id] {
			logInfo("starting new node %d (%s)", id, byID[id].Name)
			if _, err := systemctl("start", unit); err != nil {
				logError("start node %d failed: %v", id, err)
				continue
			}
			if err := waitForNode(id, 15*time.Second); err != nil {
				logWarn("node %d health check failed: %v", id, err)
			} else {
				logInfo("started node %d (%s) successfully", id, byID[id].Name)
			}
			changed = true
			continue
		}
		if dirty {
			logInfo("restarting node %d (%s) (config changed)", id, byID[id].Name)
			if _, err := systemctl("restart", unit); err != nil {
				logError("restart node %d failed: %v", id, err)
				continue
			}
			if err := waitForNode(id, 15*time.Second); err != nil {
				logWarn("node %d health check failed: %v", id, err)
			} else {
				logInfo("restarted node %d (%s) successfully", id, byID[id].Name)
			}
			changed = true
		}
	}

	// 面板里已消失/移出列表的节点：停掉并删配置
	for id := range running {
		if wantSet[id] {
			continue
		}
		unit := fmt.Sprintf(unitFmt, id)
		logInfo("stopping removed node %d", id)
		if _, err := systemctl("stop", unit); err != nil {
			logWarn("stop node %d failed: %v", id, err)
		}
		if _, err := systemctl("disable", unit); err != nil {
			logWarn("disable node %d failed: %v", id, err)
		}
		_ = os.Remove(filepath.Join(cfg.ConfigDir, fmt.Sprintf("%d.yml", id)))
		changed = true
	}

	if !changed {
		logInfo("no changes, %d nodes running (took %v)", len(running), time.Since(start))
	} else {
		logInfo("sync completed in %v", time.Since(start))
	}
}
