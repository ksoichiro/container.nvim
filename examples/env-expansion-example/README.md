# Environment Variable Expansion Example

This example demonstrates the **environment variable expansion** feature for `${containerEnv:variable}` syntax in devcontainer.json.

## Features Demonstrated

### 1. PATH Expansion
```json
"PATH": "/usr/local/custom/bin:${containerEnv:PATH}"
```
- Expands to: `/usr/local/custom/bin:/usr/local/bin:/usr/bin:/bin`
- Custom path is prepended to the standard container PATH

### 2. Standard Environment Variables
```json
"HOME_VAR": "${containerEnv:HOME}",
"SHELL_VAR": "${containerEnv:SHELL}",
"USER_VAR": "${containerEnv:USER}"
```
- These expand to their fallback values during container creation

### 3. Custom Variables
```json
"CUSTOM_VAR": "This is a custom value without expansion"
```
- Regular environment variables work as expected

## How to Test

1. **Start the container**:
   ```
   :ContainerStart
   ```

2. **Check the postCreateCommand output** to see the expanded environment variables

3. **Run the test program**:
   ```
   :ContainerExec go run main.go
   ```

4. **Check environment variables interactively**:
   ```
   :ContainerExec echo $PATH
   :ContainerExec echo $HOME_VAR
   ```

## Expected Results

- `PATH` should contain `/usr/local/custom/bin` at the beginning
- `HOME_VAR` should be `/root` (expanded from `${containerEnv:HOME}`)
- `SHELL_VAR` should be `/bin/sh` (expanded from `${containerEnv:SHELL}`)
- `USER_VAR` should be `root` (expanded from `${containerEnv:USER}`)
- `CUSTOM_VAR` should be the literal string

## Technical Details

This example tests the fix for the environment variable expansion issue where `${containerEnv:PATH}` was previously failing container creation. The implementation now:

1. **Expands known variables** to appropriate fallback values
2. **Maintains compatibility** with VS Code Dev Containers syntax
3. **Preserves unknown variables** as placeholders for safety

## Previous vs Current Behavior

| Before | After |
|--------|-------|
| `"PATH": "/custom:${containerEnv:PATH}"` → **Container creation fails** | `"PATH": "/custom:${containerEnv:PATH}"` → **Expands to working PATH** |
| Docker error: `unknown variable` | Docker succeeds with proper PATH |
