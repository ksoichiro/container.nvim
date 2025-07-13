#!/usr/bin/env lua

-- Integration tests for container.lsp.init module
-- Tests LSP initialization in real container environments

local helpers = require('test.helpers.init')

-- Test module
local M = {}

-- Test configuration
local test_config = {
  timeout = 15000, -- 15 seconds for container operations
  container_name = 'test_lsp_init_container',
  test_workspace = vim.fn.tempname() .. '_lsp_init_test',
  devcontainer_path = nil,
}

-- Setup test environment with Go project
local function setup_go_test_project()
  -- Create temporary test workspace
  vim.fn.mkdir(test_config.test_workspace, 'p')

  -- Create go.mod
  local go_mod_content = [[module github.com/test/lsp-init

go 1.21

require (
    github.com/stretchr/testify v1.8.4
)
]]

  local go_mod_file = test_config.test_workspace .. '/go.mod'
  local mod_file = io.open(go_mod_file, 'w')
  if mod_file then
    mod_file:write(go_mod_content)
    mod_file:close()
  end

  -- Create main.go with complex structure for LSP testing
  local main_go_content = [[package main

import (
    "fmt"
    "log"
    "net/http"
    "github.com/test/lsp-init/internal/utils"
)

// Server represents the HTTP server
type Server struct {
    port   int
    router *http.ServeMux
}

// NewServer creates a new server instance
func NewServer(port int) *Server {
    return &Server{
        port:   port,
        router: http.NewServeMux(),
    }
}

// Start starts the HTTP server
func (s *Server) Start() error {
    s.setupRoutes()
    addr := fmt.Sprintf(":%d", s.port)
    log.Printf("Starting server on %s", addr)
    return http.ListenAndServe(addr, s.router)
}

// setupRoutes configures the HTTP routes
func (s *Server) setupRoutes() {
    s.router.HandleFunc("/", s.handleHome)
    s.router.HandleFunc("/health", s.handleHealth)
    s.router.HandleFunc("/api/users", s.handleUsers)
}

// handleHome handles the home route
func (s *Server) handleHome(w http.ResponseWriter, r *http.Request) {
    message := utils.GetWelcomeMessage()
    fmt.Fprintf(w, "Welcome! %s", message)
}

// handleHealth handles the health check route
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
    fmt.Fprint(w, "OK")
}

// handleUsers handles the users API route
func (s *Server) handleUsers(w http.ResponseWriter, r *http.Request) {
    switch r.Method {
    case http.MethodGet:
        s.getUsers(w, r)
    case http.MethodPost:
        s.createUser(w, r)
    default:
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
    }
}

// getUsers returns all users
func (s *Server) getUsers(w http.ResponseWriter, r *http.Request) {
    users := []string{"Alice", "Bob", "Charlie"}
    fmt.Fprintf(w, "Users: %v", users)
}

// createUser creates a new user
func (s *Server) createUser(w http.ResponseWriter, r *http.Request) {
    fmt.Fprint(w, "User created")
}

func main() {
    server := NewServer(8080)
    if err := server.Start(); err != nil {
        log.Fatal(err)
    }
}
]]

  local main_go_file = test_config.test_workspace .. '/main.go'
  local main_file = io.open(main_go_file, 'w')
  if main_file then
    main_file:write(main_go_content)
    main_file:close()
  end

  -- Create internal/utils package
  vim.fn.mkdir(test_config.test_workspace .. '/internal/utils', 'p')

  local utils_content = [[package utils

import "time"

// GetWelcomeMessage returns a welcome message with timestamp
func GetWelcomeMessage() string {
    return "Hello from LSP test! Time: " + time.Now().Format(time.RFC3339)
}

// ProcessData processes input data
func ProcessData(input string) string {
    if input == "" {
        return "empty"
    }
    return "processed: " + input
}

// Calculator provides calculation functions
type Calculator struct {
    history []string
}

// NewCalculator creates a new calculator
func NewCalculator() *Calculator {
    return &Calculator{
        history: make([]string, 0),
    }
}

// Add performs addition
func (c *Calculator) Add(a, b int) int {
    result := a + b
    c.addToHistory(fmt.Sprintf("%d + %d = %d", a, b, result))
    return result
}

// Multiply performs multiplication
func (c *Calculator) Multiply(a, b int) int {
    result := a * b
    c.addToHistory(fmt.Sprintf("%d * %d = %d", a, b, result))
    return result
}

// GetHistory returns calculation history
func (c *Calculator) GetHistory() []string {
    return c.history
}

// addToHistory adds an entry to calculation history
func (c *Calculator) addToHistory(entry string) {
    c.history = append(c.history, entry)
}
]]

  local utils_file = test_config.test_workspace .. '/internal/utils/utils.go'
  local utils_handle = io.open(utils_file, 'w')
  if utils_handle then
    utils_handle:write(utils_content)
    utils_handle:close()
  end

  -- Create test files
  local main_test_content = [[package main

import (
    "net/http"
    "net/http/httptest"
    "testing"
    "github.com/test/lsp-init/internal/utils"
)

func TestNewServer(t *testing.T) {
    server := NewServer(8080)
    if server.port != 8080 {
        t.Errorf("Expected port 8080, got %d", server.port)
    }
}

func TestHandleHome(t *testing.T) {
    server := NewServer(8080)
    server.setupRoutes()

    req := httptest.NewRequest(http.MethodGet, "/", nil)
    w := httptest.NewRecorder()

    server.handleHome(w, req)

    if w.Code != http.StatusOK {
        t.Errorf("Expected status OK, got %v", w.Code)
    }
}

func TestHandleHealth(t *testing.T) {
    server := NewServer(8080)

    req := httptest.NewRequest(http.MethodGet, "/health", nil)
    w := httptest.NewRecorder()

    server.handleHealth(w, req)

    if w.Code != http.StatusOK {
        t.Errorf("Expected status OK, got %v", w.Code)
    }

    if w.Body.String() != "OK" {
        t.Errorf("Expected body 'OK', got %s", w.Body.String())
    }
}

func TestUtilsIntegration(t *testing.T) {
    message := utils.GetWelcomeMessage()
    if message == "" {
        t.Error("Expected non-empty welcome message")
    }

    processed := utils.ProcessData("test")
    expected := "processed: test"
    if processed != expected {
        t.Errorf("Expected %s, got %s", expected, processed)
    }
}
]]

  local main_test_file = test_config.test_workspace .. '/main_test.go'
  local test_handle = io.open(main_test_file, 'w')
  if test_handle then
    test_handle:write(main_test_content)
    test_handle:close()
  end

  -- Create devcontainer.json
  local devcontainer_content = [[{
    "name": "Go LSP Test Environment",
    "image": "golang:1.21",
    "features": {
        "ghcr.io/devcontainers/features/common-utils:2": {
            "installZsh": true,
            "configureZshAsDefaultShell": true,
            "installOhMyZsh": true
        }
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "golang.go"
            ]
        }
    },
    "postCreateCommand": "go mod download && go install golang.org/x/tools/gopls@latest",
    "remoteUser": "root",
    "workspaceFolder": "/workspace"
}]]

  vim.fn.mkdir(test_config.test_workspace .. '/.devcontainer', 'p')
  local devcontainer_file = test_config.test_workspace .. '/.devcontainer/devcontainer.json'
  local dc_handle = io.open(devcontainer_file, 'w')
  if dc_handle then
    dc_handle:write(devcontainer_content)
    dc_handle:close()
  end

  test_config.devcontainer_path = devcontainer_file

  return {
    workspace = test_config.test_workspace,
    main_go = main_go_file,
    utils_go = utils_file,
    test_file = main_test_file,
    devcontainer = devcontainer_file,
  }
end

-- Cleanup test environment
local function cleanup_test_env()
  if vim.fn.isdirectory(test_config.test_workspace) == 1 then
    vim.fn.delete(test_config.test_workspace, 'rf')
  end
end

-- Wait for condition with timeout
local function wait_for_condition(condition_fn, timeout_ms, check_interval)
  timeout_ms = timeout_ms or test_config.timeout
  check_interval = check_interval or 200

  local start_time = vim.loop.hrtime()

  while (vim.loop.hrtime() - start_time) / 1000000 < timeout_ms do
    if condition_fn() then
      return true
    end
    vim.wait(check_interval)
  end

  return false
end

-- Test: Container setup and LSP auto-initialization
function M.test_container_lsp_auto_initialization()
  local project = setup_go_test_project()

  -- Change to test workspace
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    -- Initialize container plugin
    local container = require('container')
    container.setup({
      log_level = 'debug',
      lsp = {
        auto_setup = true,
        timeout = 10000,
      },
    })

    -- Open Go file to trigger LSP initialization
    vim.cmd('edit ' .. project.main_go)

    -- Build and start container
    container.build()

    -- Wait for container to be ready
    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000) -- 30 seconds for container build

    if not container_ready then
      error('Container did not become ready within timeout')
    end

    local state = container.get_state()
    local container_id = state.current_container

    -- Wait for LSP auto-initialization
    local lsp_ready = wait_for_condition(function()
      local lsp = require('container.lsp.init')
      local lsp_state = lsp.get_state()

      -- Check if gopls client exists and is functional
      local exists, client_id = lsp.client_exists('gopls')
      if not exists then
        return false
      end

      local client = vim.lsp.get_client_by_id(client_id)
      return client and client.initialized and not client.is_stopped()
    end, 15000) -- 15 seconds for LSP initialization

    if lsp_ready then
      local lsp = require('container.lsp.init')

      -- Verify LSP state
      local lsp_state = lsp.get_state()
      assert(lsp_state.container_id == container_id, 'LSP should have correct container ID')
      assert(vim.tbl_contains(lsp_state.clients, 'gopls'), 'gopls client should be active')

      -- Verify server detection
      local servers = lsp_state.servers
      assert(servers.gopls ~= nil, 'gopls should be detected')
      assert(servers.gopls.available == true, 'gopls should be available')

      success = true
    else
      error('LSP did not initialize within timeout')
    end

    -- Cleanup
    container.stop()
  end)

  -- Restore directory and cleanup
  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: Manual LSP setup and server detection
function M.test_manual_lsp_setup()
  local project = setup_go_test_project()
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    local container = require('container')
    container.setup({ log_level = 'debug' })

    -- Build container without auto LSP
    container.build()

    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000)

    if not container_ready then
      error('Container not ready for manual LSP test')
    end

    local state = container.get_state()
    local container_id = state.current_container

    -- Manual LSP setup
    local lsp = require('container.lsp.init')
    lsp.setup({
      auto_setup = false,
      timeout = 8000,
    })

    lsp.set_container_id(container_id)

    -- Test server detection
    local servers = lsp.detect_language_servers()
    assert(type(servers) == 'table', 'Server detection should return table')
    assert(servers.gopls ~= nil, 'gopls should be detected')
    assert(servers.gopls.available == true, 'gopls should be available')
    assert(servers.gopls.path:match('/gopls$'), 'gopls path should be valid')

    -- Test manual client creation
    lsp.create_lsp_client('gopls', servers.gopls)

    local client_ready = wait_for_condition(function()
      local exists, client_id = lsp.client_exists('gopls')
      if not exists then
        return false
      end

      local client = vim.lsp.get_client_by_id(client_id)
      return client and client.initialized
    end, 10000)

    assert(client_ready, 'LSP client should be ready after manual setup')

    -- Test LSP functionality
    local lsp_state = lsp.get_state()
    assert(lsp_state.container_id == container_id, 'Container ID should be set')
    assert(#lsp_state.clients > 0, 'At least one client should be active')

    success = true

    -- Cleanup
    lsp.stop_all()
    container.stop()
  end)

  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: LSP commands and path transformation
function M.test_lsp_commands_integration()
  local project = setup_go_test_project()
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    local container = require('container')
    container.setup({
      log_level = 'debug',
      lsp = { auto_setup = true },
    })

    -- Open main Go file
    vim.cmd('edit ' .. project.main_go)

    container.build()

    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000)

    if not container_ready then
      error('Container not ready for commands test')
    end

    -- Wait for LSP to be ready
    local lsp_ready = wait_for_condition(function()
      local lsp = require('container.lsp.init')
      local exists, client_id = lsp.client_exists('gopls')
      if not exists then
        return false
      end

      local client = vim.lsp.get_client_by_id(client_id)
      return client and client.initialized and not client.is_stopped()
    end, 15000)

    if not lsp_ready then
      error('LSP not ready for commands test')
    end

    -- Test LSP commands
    local commands = require('container.lsp.commands')
    commands.setup({
      host_workspace = test_config.test_workspace,
      container_workspace = '/workspace',
    })

    -- Position cursor on a symbol (Server struct)
    vim.api.nvim_win_set_cursor(0, { 9, 6 }) -- Line 9, on "Server"

    -- Test hover command
    local hover_result = commands.hover({ server_name = 'gopls' })
    assert(hover_result == true, 'Hover command should succeed')

    -- Test definition command (on NewServer function)
    vim.api.nvim_win_set_cursor(0, { 14, 5 }) -- Line 14, on "NewServer"
    commands.definition({ server_name = 'gopls' })

    -- Test references command
    commands.references({ server_name = 'gopls' })

    success = true

    container.stop()
  end)

  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: LSP error handling and recovery
function M.test_lsp_error_handling()
  local project = setup_go_test_project()
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    local container = require('container')
    container.setup({ log_level = 'debug' })

    container.build()

    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000)

    if not container_ready then
      error('Container not ready for error handling test')
    end

    local state = container.get_state()
    local container_id = state.current_container

    local lsp = require('container.lsp.init')
    lsp.setup()
    lsp.set_container_id(container_id)

    -- Test health check
    local health = lsp.health_check()
    assert(type(health) == 'table', 'Health check should return table')
    assert(health.container_connected == true, 'Should report container connected')

    -- Test server diagnosis
    local diagnosis = lsp.diagnose_lsp_server('gopls')
    assert(type(diagnosis) == 'table', 'Diagnosis should return table')

    -- Test diagnosis for non-existent server
    local bad_diagnosis = lsp.diagnose_lsp_server('nonexistent_server')
    assert(bad_diagnosis.available == false, 'Non-existent server should not be available')
    assert(type(bad_diagnosis.suggestions) == 'table', 'Should provide suggestions')

    -- Test recovery mechanism
    lsp.recover_all_lsp_servers()

    -- Test retry mechanism
    lsp.retry_lsp_server_setup('gopls', 1)

    success = true

    container.stop()
  end)

  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: Multiple client management
function M.test_multiple_client_management()
  local project = setup_go_test_project()
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    local container = require('container')
    container.setup({ log_level = 'debug' })

    container.build()

    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000)

    if not container_ready then
      error('Container not ready for multiple client test')
    end

    local state = container.get_state()
    local container_id = state.current_container

    local lsp = require('container.lsp.init')
    lsp.setup({ auto_setup = false })
    lsp.set_container_id(container_id)

    -- Detect all available servers
    local servers = lsp.detect_language_servers()

    local created_clients = 0
    for name, server in pairs(servers) do
      if server.available then
        lsp.create_lsp_client(name, server)
        created_clients = created_clients + 1
      end
    end

    assert(created_clients > 0, 'At least one client should be created')

    -- Wait for clients to initialize
    local clients_ready = wait_for_condition(function()
      local lsp_state = lsp.get_state()
      return #lsp_state.clients == created_clients
    end, 10000)

    assert(clients_ready, 'All created clients should be in state')

    -- Test stopping specific client
    if vim.tbl_contains(lsp.get_state().clients, 'gopls') then
      lsp.stop_client('gopls')

      local client_stopped = wait_for_condition(function()
        local exists = lsp.client_exists('gopls')
        return not exists
      end, 5000)

      assert(client_stopped, 'Specific client should be stopped')
    end

    -- Test stopping all clients
    lsp.stop_all()

    local all_stopped = wait_for_condition(function()
      local lsp_state = lsp.get_state()
      return #lsp_state.clients == 0
    end, 5000)

    assert(all_stopped, 'All clients should be stopped')

    success = true

    container.stop()
  end)

  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: Buffer attachment and detachment
function M.test_buffer_attachment()
  local project = setup_go_test_project()
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  local success = false

  pcall(function()
    local container = require('container')
    container.setup({
      log_level = 'debug',
      lsp = { auto_setup = true },
    })

    -- Open multiple Go files
    vim.cmd('edit ' .. project.main_go)
    local main_buf = vim.api.nvim_get_current_buf()

    vim.cmd('split ' .. project.utils_go)
    local utils_buf = vim.api.nvim_get_current_buf()

    container.build()

    local container_ready = wait_for_condition(function()
      local state = container.get_state()
      return state.current_container ~= nil
    end, 30000)

    if not container_ready then
      error('Container not ready for buffer attachment test')
    end

    -- Wait for LSP to attach to buffers
    local lsp_attached = wait_for_condition(function()
      local lsp = require('container.lsp.init')
      local exists, client_id = lsp.client_exists('gopls')
      if not exists then
        return false
      end

      local client = vim.lsp.get_client_by_id(client_id)
      if not client or not client.initialized then
        return false
      end

      -- Check if client is attached to both buffers
      local main_clients = vim.lsp.get_clients({ bufnr = main_buf })
      local utils_clients = vim.lsp.get_clients({ bufnr = utils_buf })

      local main_attached = false
      local utils_attached = false

      for _, c in ipairs(main_clients) do
        if c.name == 'container_gopls' then
          main_attached = true
          break
        end
      end

      for _, c in ipairs(utils_clients) do
        if c.name == 'container_gopls' then
          utils_attached = true
          break
        end
      end

      return main_attached and utils_attached
    end, 15000)

    assert(lsp_attached, 'LSP should be attached to Go buffers')

    success = true

    container.stop()
  end)

  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Main test runner
function M.run_all_integration_tests()
  local tests = {
    { name = 'Container LSP Auto-initialization', func = M.test_container_lsp_auto_initialization },
    { name = 'Manual LSP Setup', func = M.test_manual_lsp_setup },
    { name = 'LSP Commands Integration', func = M.test_lsp_commands_integration },
    { name = 'LSP Error Handling', func = M.test_lsp_error_handling },
    { name = 'Multiple Client Management', func = M.test_multiple_client_management },
    { name = 'Buffer Attachment', func = M.test_buffer_attachment },
  }

  local results = {}
  local passed = 0
  local total = #tests

  print('Running LSP Init Integration Tests...')
  print('====================================')

  for _, test in ipairs(tests) do
    print('\nRunning: ' .. test.name)

    local ok, result = pcall(test.func)

    if ok and result then
      print('✓ PASSED: ' .. test.name)
      passed = passed + 1
      results[test.name] = 'PASSED'
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test.name .. ' - ' .. error_msg)
      results[test.name] = 'FAILED: ' .. error_msg
    end
  end

  print('\n====================================')
  print(string.format('LSP Init Integration Tests Complete: %d/%d passed', passed, total))

  if passed == total then
    print('All LSP init integration tests passed! ✓')
    return true
  else
    print('Some LSP init integration tests failed. ✗')
    return false
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  M.run_all_integration_tests()
end

return M
