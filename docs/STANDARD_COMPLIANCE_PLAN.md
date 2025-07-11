# Standard Compliance Migration Plan

This document outlines the plan to improve Dev Container specification compliance while maintaining container.nvim's unique features.

## Current Non-Standard Implementations

### 1. Dynamic Port Forwarding
- **Current**: `"auto:3000"`, `"range:8000-8010:3000"` in `forwardPorts`
- **Issue**: Not recognized by VSCode or other tools
- **Priority**: Medium

### 2. Custom Environment Variables
- **Current**: Multiple context-specific environment settings
- **Issue**: Duplicates standard `containerEnv`/`remoteEnv` functionality
- **Priority**: High

### 3. Language Presets
- **Current**: Hardcoded language-specific paths
- **Issue**: Not portable across different images
- **Priority**: Low

## Migration Strategy

### Phase 1: Dual Support (v0.6.0) ✅ COMPLETED
Maintain backward compatibility while adding standard support:

1. **Port Forwarding Enhancement** ✅ COMPLETED
   - Implemented automatic detection of non-standard dynamic port syntax
   - Shows deprecation warnings when `auto:` or `range:` syntax is used
   - Automatically migrates to `customizations.container.nvim.dynamicPorts`
   - Updates `forwardPorts` to contain only standard port numbers
   - Both standard and custom formats are now supported

2. **Environment Variable Standardization**
   ```lua
   -- Support standard properties first, fall back to custom
   function M.get_environment(config, context)
     -- 1. Check standard containerEnv/remoteEnv
     local env = config.containerEnv or config.remoteEnv or {}

     -- 2. Apply custom extensions if present
     if config.customizations and config.customizations['container.nvim'] then
       -- Merge with deprecation warning
     end

     return env
   end
   ```

### Phase 2: Documentation Update (v0.6.1)
1. Update all examples to use standard format
2. Add migration guide for existing users
3. Update README with compatibility notes

### Phase 3: Deprecation Warnings (v0.7.0)
1. Show warnings for non-standard usage
2. Provide automatic migration suggestions
3. Create `:ContainerMigrateConfig` command

### Phase 4: Full Compliance (v1.0.0)
1. Remove support for legacy syntax in `forwardPorts`
2. Keep extensions only in `customizations` section
3. Maintain full backward compatibility via customizations

## Implementation Details

### 1. Automatic Config Migration
```lua
-- New module: lua/container/migrate.lua
local M = {}

function M.migrate_config(config)
  local migrated = vim.deepcopy(config)
  local changes = {}

  -- Migrate dynamic ports
  if has_dynamic_ports(migrated.forwardPorts) then
    local dynamic, standard = split_ports(migrated.forwardPorts)
    migrated.forwardPorts = standard
    ensure_customizations(migrated)
    migrated.customizations['container.nvim'].dynamicPorts = dynamic
    table.insert(changes, "Moved dynamic ports to customizations")
  end

  -- Migrate environment variables
  if has_custom_env_contexts(migrated) then
    -- Merge into containerEnv/remoteEnv
    table.insert(changes, "Migrated custom environment contexts")
  end

  return migrated, changes
end
```

### 2. Compatibility Layer
```lua
-- Maintain compatibility while encouraging migration
function M.normalize_config(config)
  -- Always work with migrated config internally
  local migrated = M.migrate_config(config)

  -- But respect user's original format
  if not config._migrated then
    log.info("Consider updating your devcontainer.json for better compatibility")
  end

  return migrated
end
```

### 3. User-Friendly Migration Command
```vim
:ContainerMigrateConfig
" Shows diff of changes
" Offers to update devcontainer.json
" Preserves formatting and comments
```

## Benefits

1. **Full VSCode Compatibility**: Teams can use both tools seamlessly
2. **Standards Compliance**: Follow official specification
3. **Feature Preservation**: Keep all container.nvim enhancements
4. **Smooth Transition**: No breaking changes for users

## Timeline

- **v0.6.0** (Current): Implement dual support
- **v0.6.1** (2 weeks): Update documentation
- **v0.7.0** (1 month): Add deprecation warnings
- **v1.0.0** (3 months): Full compliance

## Action Items

1. [ ] Implement config migration module
2. [ ] Add compatibility layer to parser
3. [ ] Create migration command
4. [ ] Update test suite for both formats
5. [ ] Write migration guide for users
6. [ ] Update all documentation examples

## Conclusion

This migration plan ensures container.nvim becomes fully compliant with the Dev Container specification while preserving its innovative features. Users benefit from better tool compatibility without losing functionality.
