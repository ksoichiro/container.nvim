-- Test for dynamic port migration to standard compliant format
local mock = require('test.test_mock')
local parser = require('container.parser')

describe('Dynamic Port Migration', function()
  before_each(function()
    mock.setup()
  end)

  after_each(function()
    mock.teardown()
  end)

  it('should detect and migrate auto: syntax', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 3000, 'auto:8080', 5000 },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that deprecated ports were detected
    assert.equals(1, #parsed.deprecated_ports)
    assert.equals('auto:8080', parsed.deprecated_ports[1])

    -- Check that forwardPorts now contains only standard ports
    assert.equals(3, #parsed.forwardPorts)
    assert.equals(3000, parsed.forwardPorts[1])
    assert.equals(8080, parsed.forwardPorts[2]) -- auto:8080 -> 8080
    assert.equals(5000, parsed.forwardPorts[3])

    -- Check that dynamic ports were migrated to customizations
    assert.not_nil(parsed.customizations)
    assert.not_nil(parsed.customizations['container.nvim'])
    assert.not_nil(parsed.customizations['container.nvim'].dynamicPorts)
    assert.equals(1, #parsed.customizations['container.nvim'].dynamicPorts)
    assert.equals('auto:8080', parsed.customizations['container.nvim'].dynamicPorts[1])
  end)

  it('should detect and migrate range: syntax', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 'range:9000-9100:9229', 3000 },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that deprecated ports were detected
    assert.equals(1, #parsed.deprecated_ports)
    assert.equals('range:9000-9100:9229', parsed.deprecated_ports[1])

    -- Check that forwardPorts now contains only standard ports
    assert.equals(2, #parsed.forwardPorts)
    assert.equals(9229, parsed.forwardPorts[1]) -- range:9000-9100:9229 -> 9229
    assert.equals(3000, parsed.forwardPorts[2])

    -- Check migration to customizations
    assert.equals('range:9000-9100:9229', parsed.customizations['container.nvim'].dynamicPorts[1])
  end)

  it('should handle multiple dynamic ports', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 'auto:8080', 3000, 'range:5000-5010:5432', 'auto:9000' },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that all deprecated ports were detected
    assert.equals(3, #parsed.deprecated_ports)

    -- Check that forwardPorts contains standard ports
    assert.equals(4, #parsed.forwardPorts)
    assert.equals(8080, parsed.forwardPorts[1])
    assert.equals(3000, parsed.forwardPorts[2])
    assert.equals(5432, parsed.forwardPorts[3])
    assert.equals(9000, parsed.forwardPorts[4])

    -- Check migration
    assert.equals(3, #parsed.customizations['container.nvim'].dynamicPorts)
  end)

  it('should preserve existing customizations', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 'auto:8080' },
      customizations = {
        ['container.nvim'] = {
          existingSetting = 'value',
        },
      },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that existing customizations are preserved
    assert.equals('value', parsed.customizations['container.nvim'].existingSetting)
    assert.not_nil(parsed.customizations['container.nvim'].dynamicPorts)
  end)

  it('should not duplicate already migrated ports', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 'auto:8080' },
      customizations = {
        ['container.nvim'] = {
          dynamicPorts = { 'auto:8080' },
        },
      },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that port is not duplicated
    assert.equals(1, #parsed.customizations['container.nvim'].dynamicPorts)
  end)

  it('should work with no dynamic ports', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      forwardPorts = { 3000, 8080, 5432 },
    }

    local parsed = parser.parse(nil, {}, config)

    -- Check that no deprecated ports were detected
    assert.is_nil(parsed.deprecated_ports)

    -- Check that forwardPorts remains unchanged
    assert.equals(3, #parsed.forwardPorts)
    assert.equals(3000, parsed.forwardPorts[1])
    assert.equals(8080, parsed.forwardPorts[2])
    assert.equals(5432, parsed.forwardPorts[3])
  end)
end)

describe('Dynamic Port Resolution', function()
  it('should resolve ports from customizations.container.nvim.dynamicPorts only', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      customizations = {
        ['container.nvim'] = {
          dynamicPorts = { 'auto:8080', 'range:9000-9100:9229' },
        },
      },
      project_id = 'test-project',
    }

    local plugin_config = {
      port_forwarding = {
        enable_dynamic_ports = true,
        port_range_start = 10000,
        port_range_end = 20000,
      },
    }

    -- Mock port utils to verify it receives the dynamic ports
    local port_utils_mock = {}
    local received_port_specs = nil

    function port_utils_mock.resolve_dynamic_ports(port_specs, project_id, options)
      received_port_specs = port_specs
      return {
        {
          type = 'dynamic',
          container_port = 8080,
          host_port = 10000,
          original_spec = 'auto:8080',
        },
        {
          type = 'dynamic',
          container_port = 9229,
          host_port = 9000,
          original_spec = 'range:9000-9100:9229',
        },
      },
        nil
    end

    package.loaded['container.utils.port'] = port_utils_mock

    local result_config = parser.resolve_dynamic_ports(config, plugin_config)

    -- Verify that dynamic ports from customizations were included
    assert.not_nil(received_port_specs)
    assert.equals(2, #received_port_specs)
    assert.equals('auto:8080', received_port_specs[1])
    assert.equals('range:9000-9100:9229', received_port_specs[2])

    -- Verify that ports were resolved
    assert.not_nil(result_config.normalized_ports)
    assert.equals(2, #result_config.normalized_ports)
  end)

  it('should work when no forwardPorts is specified', function()
    local config = {
      name = 'test',
      image = 'test:latest',
      customizations = {
        ['container.nvim'] = {
          dynamicPorts = { 'auto:3000' },
        },
      },
      project_id = 'test-project',
    }

    local plugin_config = {
      port_forwarding = {
        enable_dynamic_ports = true,
        port_range_start = 10000,
        port_range_end = 20000,
      },
    }

    -- Mock port utils
    local port_utils_mock = {}
    function port_utils_mock.resolve_dynamic_ports(port_specs, project_id, options)
      return {
        {
          type = 'dynamic',
          container_port = 3000,
          host_port = 10000,
          original_spec = 'auto:3000',
        },
      },
        nil
    end

    package.loaded['container.utils.port'] = port_utils_mock

    local result_config = parser.resolve_dynamic_ports(config, plugin_config)

    -- Should have processed the dynamic port even without forwardPorts
    assert.not_nil(result_config.normalized_ports)
    assert.equals(1, #result_config.normalized_ports)
    assert.equals(3000, result_config.normalized_ports[1].container_port)
    assert.equals(10000, result_config.normalized_ports[1].host_port)
  end)
end)
