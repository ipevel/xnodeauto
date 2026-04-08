package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// ---------- version info ----------

var (
	Version   = "1.0.0"
	BuildTime = "unknown"
)

// ---------- config ----------

const (
	configDir      = "/etc/xboard-node"
	syncConfigPath = configDir + "/sync.yml"
	tokenCachePath = configDir + "/.token"
	serviceName    = "xboard-node@%d.service"
)

type SyncConfig struct {
	XboardURL     string `yaml:"xboard_url"`
	AdminPath     string `yaml:"admin_path"`
	AdminEmail    string `yaml:"admin_email"`
	AdminPassword string `yaml:"admin_password"`
	PanelToken    string `yaml:"panel_token"`
	ManualNodeIDs []int  `yaml:"manual_node_ids"` // 手动指定的节点ID列表（可选）
}

func loadConfig() (*SyncConfig, error) {
	data, err := os.ReadFile(syncConfigPath)
	if err != nil {
		return nil, fmt.Errorf("config not found: %s\n  Run install.sh with config params", syncConfigPath)
	}

	var cfg SyncConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	var missing []string
	if cfg.XboardURL == "" {
		missing = append(missing, "xboard_url")
	}
	if cfg.AdminPath == "" {
		missing = append(missing, "admin_path")
	}
	if cfg.AdminEmail == "" {
		missing = append(missing, "admin_email")
	}
	if cfg.AdminPassword == "" {
		missing = append(missing, "admin_password")
	}
	if cfg.PanelToken == "" {
		missing = append(missing, "panel_token")
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("missing config keys: %s", strings.Join(missing, ", "))
	}

	return &cfg, nil
}

// ---------- logging ----------

func logInfo(format string, args ...interface{}) {
	fmt.Printf("[%s] [INFO] %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

func logWarn(format string, args ...interface{}) {
	fmt.Printf("[%s] [WARN] %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

func logError(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "[%s] [ERROR] %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

func logDebug(format string, args ...interface{}) {
	if os.Getenv("SYNC_NODES_DEBUG") != "" {
		fmt.Printf("[%s] [DEBUG] %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
	}
}

// ---------- IP detection ----------

func getMyIPs() map[string]bool {
	ips := make(map[string]bool)

	// local outbound IP (UDP dial, no packet sent)
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		logWarn("local ip detect failed: %v", err)
	} else {
		addr := conn.LocalAddr().(*net.UDPAddr)
		ips[addr.IP.String()] = true
		conn.Close()
		logDebug("detected local ip: %s", addr.IP.String())
	}

	// public IP via api.ipify.org with timeout
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://api.ipify.org")
	if err != nil {
		logWarn("public ip detect failed: %v", err)
	} else {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		ip := strings.TrimSpace(string(body))
		if ip != "" {
			ips[ip] = true
			logDebug("detected public ip: %s", ip)
		}
	}

	return ips
}

func hostToIP(host string) (string, error) {
	if host == "" {
		return "", fmt.Errorf("empty host")
	}
	addrs, err := net.LookupHost(host)
	if err != nil {
		return "", fmt.Errorf("lookup failed: %w", err)
	}
	if len(addrs) == 0 {
		return "", fmt.Errorf("no addresses found")
	}
	return addrs[0], nil
}

// ---------- Xboard API ----------

type Node struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	Host string `json:"host"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginResponse struct {
	Data struct {
		AuthData string `json:"auth_data"`
		Token    string `json:"token"`
	} `json:"data"`
}

type nodesResponse struct {
	Data []Node `json:"data"`
}

type apiClient struct {
	cfg       *SyncConfig
	client    *http.Client
	token     string
	maxRetry  int
}

func newAPIClient(cfg *SyncConfig) *apiClient {
	return &apiClient{
		cfg: cfg,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		maxRetry: 3,
	}
}

func (c *apiClient) login() error {
	body, _ := json.Marshal(loginRequest{
		Email:    c.cfg.AdminEmail,
		Password: c.cfg.AdminPassword,
	})

	resp, err := c.client.Post(
		c.cfg.XboardURL+"/api/v2/passport/auth/login",
		"application/json",
		bytes.NewReader(body),
	)
	if err != nil {
		return fmt.Errorf("login request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("login failed (status %d): %s", resp.StatusCode, string(respBody))
	}

	var lr loginResponse
	if err := json.NewDecoder(resp.Body).Decode(&lr); err != nil {
		return fmt.Errorf("parse login response: %w", err)
	}

	token := lr.Data.AuthData
	if token == "" {
		token = lr.Data.Token
	}
	if token == "" {
		return fmt.Errorf("login response has no token")
	}

	c.token = token
	// cache token with restricted permissions
	if err := os.WriteFile(tokenCachePath, []byte(token), 0600); err != nil {
		logWarn("failed to cache token: %v", err)
	}
	return nil
}

func (c *apiClient) getToken() error {
	// try cached token
	data, err := os.ReadFile(tokenCachePath)
	if err == nil {
		token := strings.TrimSpace(string(data))
		if token != "" {
			c.token = token
			logDebug("using cached token")
			return nil
		}
	}
	return c.login()
}

func (c *apiClient) doRequest(method, url string) (*http.Response, error) {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	return c.client.Do(req)
}

func (c *apiClient) fetchNodes() ([]Node, error) {
	if err := c.getToken(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/api/v2/%s/server/manage/getNodes", c.cfg.XboardURL, c.cfg.AdminPath)

	var lastErr error
	for attempt := 1; attempt <= c.maxRetry; attempt++ {
		if attempt > 1 {
			logInfo("retry attempt %d/%d", attempt, c.maxRetry)
			// re-login on retry
			if err := c.login(); err != nil {
				lastErr = err
				continue
			}
		}

		resp, err := c.doRequest("GET", url)
		if err != nil {
			lastErr = fmt.Errorf("fetch nodes: %w", err)
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			lastErr = fmt.Errorf("unauthorized (status %d)", resp.StatusCode)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			lastErr = fmt.Errorf("fetch nodes failed (status %d): %s", resp.StatusCode, string(body))
			continue
		}

		var nr nodesResponse
		if err := json.NewDecoder(resp.Body).Decode(&nr); err != nil {
			lastErr = fmt.Errorf("parse nodes response: %w", err)
			continue
		}

		return nr.Data, nil
	}

	return nil, fmt.Errorf("all retries failed: %w", lastErr)
}

func myNodes(allNodes []Node, myIPs map[string]bool) []Node {
	var result []Node
	for _, n := range allNodes {
		ip, err := hostToIP(n.Host)
		if err != nil {
			logDebug("node %d (%s) host '%s' lookup failed: %v", n.ID, n.Name, n.Host, err)
			continue
		}
		if myIPs[ip] {
			result = append(result, n)
			logDebug("node %d (%s) matched: %s -> %s", n.ID, n.Name, n.Host, ip)
		}
	}
	return result
}

// ---------- config file management ----------

type nodeConfig struct {
	Panel struct {
		URL    string `yaml:"url"`
		Token  string `yaml:"token"`
		NodeID int    `yaml:"node_id"`
	} `yaml:"panel"`
}

func writeConfig(cfg *SyncConfig, node Node) (bool, error) {
	nc := nodeConfig{}
	nc.Panel.URL = cfg.XboardURL
	nc.Panel.Token = cfg.PanelToken
	nc.Panel.NodeID = node.ID

	newContent, err := yaml.Marshal(&nc)
	if err != nil {
		return false, err
	}

	path := filepath.Join(configDir, fmt.Sprintf("%d.yml", node.ID))

	existing, err := os.ReadFile(path)
	if err == nil && bytes.Equal(existing, newContent) {
		return false, nil
	}

	if err := os.WriteFile(path, newContent, 0644); err != nil {
		return false, err
	}
	return true, nil
}

// ---------- systemd operations ----------

func runningInstances() map[int]bool {
	out, err := exec.Command(
		"systemctl", "list-units", "--all", "--no-legend",
		"--plain", "xboard-node@*.service",
	).Output()
	if err != nil {
		return make(map[int]bool)
	}

	ids := make(map[int]bool)
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		unit := fields[0]
		// extract node_id from "xboard-node@123.service"
		atIdx := strings.Index(unit, "@")
		dotIdx := strings.Index(unit, ".service")
		if atIdx < 0 || dotIdx < 0 || atIdx >= dotIdx {
			continue
		}
		idStr := unit[atIdx+1 : dotIdx]
		if id, err := strconv.Atoi(idStr); err == nil {
			ids[id] = true
		}
	}
	return ids
}

func systemctl(action string, nodeID int) error {
	unit := fmt.Sprintf(serviceName, nodeID)
	out, err := exec.Command("systemctl", action, unit).CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl %s failed: %v, output: %s", action, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func waitForNode(nodeID int, timeout time.Duration) error {
	unit := fmt.Sprintf(serviceName, nodeID)
	deadline := time.Now().Add(timeout)
	
	for time.Now().Before(deadline) {
		out, _ := exec.Command("systemctl", "is-active", unit).Output()
		status := strings.TrimSpace(string(out))
		if status == "active" {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	
	// timeout, get status for error message
	out, _ := exec.Command("systemctl", "is-active", unit).Output()
	status := strings.TrimSpace(string(out))
	
	// get last few lines of journal for debugging
	journalOut, _ := exec.Command("journalctl", "-u", unit, "-n", "5", "--no-pager").Output()
	
	return fmt.Errorf("node %d did not start within %v (status: %s)\njournal:\n%s", 
		nodeID, timeout, status, string(journalOut))
}

// ---------- main ----------

func main() {
	// version flag
	showVersion := flag.Bool("v", false, "show version")
	flag.Parse()
	
	if *showVersion {
		fmt.Printf("sync-nodes version %s (built %s)\n", Version, BuildTime)
		os.Exit(0)
	}

	cfg, err := loadConfig()
	if err != nil {
		logError("%v", err)
		os.Exit(1)
	}

	myIPs := getMyIPs()
	if len(myIPs) == 0 {
		logError("could not detect any local IP, abort")
		os.Exit(1)
	}

	ipList := make([]string, 0, len(myIPs))
	for ip := range myIPs {
		ipList = append(ipList, ip)
	}
	logInfo("detected IPs: %v", ipList)

	os.MkdirAll(configDir, 0755)

	client := newAPIClient(cfg)
	allNodes, err := client.fetchNodes()
	if err != nil {
		logError("fetch nodes failed: %v", err)
		os.Exit(1)
	}
	logInfo("fetched %d nodes from panel", len(allNodes))

	// Build node map for lookup
	nodeMap := make(map[int]Node)
	for _, n := range allNodes {
		nodeMap[n.ID] = n
	}

	// Determine wanted nodes
	var wanted []Node
	if len(cfg.ManualNodeIDs) > 0 {
		// Use manually specified node IDs
		logInfo("using manual node IDs: %v", cfg.ManualNodeIDs)
		for _, id := range cfg.ManualNodeIDs {
			if node, ok := nodeMap[id]; ok {
				wanted = append(wanted, node)
			} else {
				logWarn("node %d not found in panel", id)
			}
		}
	} else {
		// Use IP auto-detection
		// Check if there are too many nodes (potential relay/CDN scenario)
		wanted = myNodes(allNodes, myIPs)
		if len(wanted) >= 2 {
			logError("detected %d nodes matching this server (potential relay/CDN scenario)", len(wanted))
			logError("auto-detection is disabled for safety, please use manual mode instead")
			logError("")
			logError("Add 'manual_node_ids' to your config:")
			logError("  manual_node_ids:")
			logError("    - <node_id_1>")
			logError("    - <node_id_2>")
			logError("")
			logError("Or use command: xnode add-node <node_id>")
			os.Exit(1)
		}
	}

	wantedIDs := make(map[int]bool)
	wantedMap := make(map[int]Node)
	for _, n := range wanted {
		wantedIDs[n.ID] = true
		wantedMap[n.ID] = n
	}

	currentIDs := runningInstances()
	logInfo("current running: %d nodes, should run: %d nodes", len(currentIDs), len(wantedIDs))

	hasChanges := false
	startTime := time.Now()

	// add new nodes
	for id, node := range wantedMap {
		if !currentIDs[id] {
			logInfo("starting new node %d (%s)", id, node.Name)
			
			if _, err := writeConfig(cfg, node); err != nil {
				logError("write config for node %d failed: %v", id, err)
				continue
			}
			
			if err := systemctl("enable", id); err != nil {
				logError("enable node %d failed: %v", id, err)
				continue
			}
			
			if err := systemctl("start", id); err != nil {
				logError("start node %d failed: %v", id, err)
				continue
			}
			
			// wait for node to start
			if err := waitForNode(id, 10*time.Second); err != nil {
				logError("node %d health check failed: %v", id, err)
				continue
			}
			
			logInfo("started node %d (%s) successfully", id, node.Name)
			hasChanges = true
		}
	}

	// remove old nodes
	for id := range currentIDs {
		if !wantedIDs[id] {
			logInfo("stopping removed node %d", id)
			
			if err := systemctl("stop", id); err != nil {
				logError("stop node %d failed: %v", id, err)
			}
			
			if err := systemctl("disable", id); err != nil {
				logError("disable node %d failed: %v", id, err)
			}
			
			// remove config file
			configPath := filepath.Join(configDir, fmt.Sprintf("%d.yml", id))
			if err := os.Remove(configPath); err != nil && !os.IsNotExist(err) {
				logWarn("remove config %s failed: %v", configPath, err)
			}
			
			logInfo("stopped node %d successfully", id)
			hasChanges = true
		}
	}

	// check existing nodes for config changes
	for id, node := range wantedMap {
		if currentIDs[id] {
			changed, err := writeConfig(cfg, node)
			if err != nil {
				logError("check config for node %d failed: %v", id, err)
				continue
			}
			if changed {
				logInfo("restarting node %d (%s) (config changed)", id, node.Name)
				
				if err := systemctl("restart", id); err != nil {
					logError("restart node %d failed: %v", id, err)
					continue
				}
				
				// wait for node to restart
				if err := waitForNode(id, 10*time.Second); err != nil {
					logError("node %d health check failed: %v", id, err)
					continue
				}
				
				logInfo("restarted node %d (%s) successfully", id, node.Name)
				hasChanges = true
			}
		}
	}

	elapsed := time.Since(startTime)
	
	if !hasChanges {
		logInfo("no changes, %d nodes running (took %v)", len(wantedIDs), elapsed)
	} else {
		logInfo("sync completed in %v", elapsed)
	}
}
