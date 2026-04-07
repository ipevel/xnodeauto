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
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// ---------- config ----------

const (
	configDir      = "/etc/xboard-node"
	syncConfigPath = configDir + "/sync.yml"
	tokenCachePath = configDir + "/.token"
	serviceName    = "xboard-node@%d.service"
	requestTimeout = 10 * time.Second
)

type SyncConfig struct {
	XboardURL     string `yaml:"xboard_url"`
	AdminPath     string `yaml:"admin_path"`
	AdminEmail    string `yaml:"admin_email"`
	AdminPassword string `yaml:"admin_password"`
	PanelToken    string `yaml:"panel_token"`
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

// ---------- IP detection ----------

func getMyIPs() map[string]bool {
	ips := make(map[string]bool)

	// local outbound IP (UDP dial, no packet sent)
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		fmt.Fprintf(os.Stderr, "[WARN] local ip detect failed: %v\n", err)
	} else {
		addr := conn.LocalAddr().(*net.UDPAddr)
		ips[addr.IP.String()] = true
		conn.Close()
	}

	// public IP via api.ipify.org
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://api.ipify.org")
	if err != nil {
		fmt.Fprintf(os.Stderr, "[WARN] public ip detect failed: %v\n", err)
	} else {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		ip := strings.TrimSpace(string(body))
		if ip != "" {
			ips[ip] = true
		}
	}

	return ips
}

func hostToIP(host string) string {
	if host == "" {
		return ""
	}
	addrs, err := net.LookupHost(host)
	if err != nil || len(addrs) == 0 {
		return ""
	}
	return addrs[0]
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

func login(cfg *SyncConfig) (string, error) {
	body, _ := json.Marshal(loginRequest{
		Email:    cfg.AdminEmail,
		Password: cfg.AdminPassword,
	})

	client := &http.Client{Timeout: requestTimeout}
	resp, err := client.Post(
		cfg.XboardURL+"/api/v2/passport/auth/login",
		"application/json",
		bytes.NewReader(body),
	)
	if err != nil {
		return "", fmt.Errorf("login request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("login failed (status %d): %s", resp.StatusCode, string(respBody))
	}

	var lr loginResponse
	if err := json.NewDecoder(resp.Body).Decode(&lr); err != nil {
		return "", fmt.Errorf("parse login response: %w", err)
	}

	token := lr.Data.AuthData
	if token == "" {
		token = lr.Data.Token
	}
	if token == "" {
		return "", fmt.Errorf("login response has no token")
	}

	// cache token
	os.WriteFile(tokenCachePath, []byte(token), 0600)
	return token, nil
}

func getToken(cfg *SyncConfig) (string, error) {
	data, err := os.ReadFile(tokenCachePath)
	if err == nil {
		token := strings.TrimSpace(string(data))
		if token != "" {
			return token, nil
		}
	}
	return login(cfg)
}

func fetchNodes(cfg *SyncConfig) ([]Node, error) {
	token, err := getToken(cfg)
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/api/v2/%s/server/manage/getNodes", cfg.XboardURL, cfg.AdminPath)

	doRequest := func(tok string) (*http.Response, error) {
		req, _ := http.NewRequest("GET", url, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		client := &http.Client{Timeout: requestTimeout}
		return client.Do(req)
	}

	resp, err := doRequest(token)
	if err != nil {
		return nil, fmt.Errorf("fetch nodes: %w", err)
	}
	defer resp.Body.Close()

	// token expired, re-login
	if resp.StatusCode == 401 || resp.StatusCode == 403 {
		fmt.Println("[INFO] token expired, re-login...")
		token, err = login(cfg)
		if err != nil {
			return nil, err
		}
		resp.Body.Close()
		resp, err = doRequest(token)
		if err != nil {
			return nil, fmt.Errorf("fetch nodes (retry): %w", err)
		}
		defer resp.Body.Close()
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("fetch nodes failed (status %d): %s", resp.StatusCode, string(body))
	}

	var nr nodesResponse
	if err := json.NewDecoder(resp.Body).Decode(&nr); err != nil {
		return nil, fmt.Errorf("parse nodes response: %w", err)
	}

	return nr.Data, nil
}

func myNodes(allNodes []Node, myIPs map[string]bool) []Node {
	var result []Node
	for _, n := range allNodes {
		ip := hostToIP(n.Host)
		if ip != "" && myIPs[ip] {
			result = append(result, n)
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

func systemctl(action string, nodeID int) {
	unit := fmt.Sprintf(serviceName, nodeID)
	exec.Command("systemctl", action, unit).Run()
}

// ---------- main ----------

func main() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[ERR] %v\n", err)
		os.Exit(1)
	}

	myIPs := getMyIPs()
	if len(myIPs) == 0 {
		fmt.Fprintf(os.Stderr, "[ERR] could not detect any local IP, abort\n")
		os.Exit(1)
	}

	ipList := make([]string, 0, len(myIPs))
	for ip := range myIPs {
		ipList = append(ipList, ip)
	}
	fmt.Printf("[INFO] my ips: %v\n", ipList)

	os.MkdirAll(configDir, 0755)

	allNodes, err := fetchNodes(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[ERR] fetch nodes failed: %v\n", err)
		os.Exit(1)
	}

	wanted := myNodes(allNodes, myIPs)
	wantedIDs := make(map[int]bool)
	wantedMap := make(map[int]Node)
	for _, n := range wanted {
		wantedIDs[n.ID] = true
		wantedMap[n.ID] = n
	}

	currentIDs := runningInstances()

	hasChanges := false

	// add new nodes
	for id, node := range wantedMap {
		if !currentIDs[id] {
			writeConfig(cfg, node)
			systemctl("enable", id)
			systemctl("start", id)
			fmt.Printf("[+] started node %d (%s)\n", id, node.Name)
			hasChanges = true
		}
	}

	// remove old nodes
	for id := range currentIDs {
		if !wantedIDs[id] {
			systemctl("stop", id)
			systemctl("disable", id)
			fmt.Printf("[-] stopped node %d\n", id)
			hasChanges = true
		}
	}

	// check existing nodes for config changes
	for id, node := range wantedMap {
		if currentIDs[id] {
			changed, _ := writeConfig(cfg, node)
			if changed {
				systemctl("restart", id)
				fmt.Printf("[~] restarted node %d (%s) (config changed)\n", id, node.Name)
				hasChanges = true
			}
		}
	}

	if !hasChanges {
		fmt.Printf("[INFO] no changes, %d nodes running\n", len(wantedIDs))
	}
}
