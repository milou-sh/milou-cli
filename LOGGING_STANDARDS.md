# Milou CLI Logging Standards

## Overview
All Milou CLI modules now use a standardized logging system based on the `milou_log()` function.

## Usage Patterns

### 1. Core Modules (lib/core/*.sh)
Core modules should expect `milou_log()` to be available and fail gracefully if not:

```bash
# At the top of each core module
if ! command -v milou_log >/dev/null 2>&1; then
    echo "ERROR: milou_log function not available" >&2
    exit 1
fi
```

### 2. System Modules (lib/system/*.sh, lib/docker/*.sh, lib/user/*.sh)
System modules should try to load logging and fail gracefully:

```bash
# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    # Try to load logging module
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
            echo "ERROR: Cannot load logging module" >&2
            exit 1
        }
    else
        echo "ERROR: milou_log function not available and cannot load logging module" >&2
        echo "INFO: Ensure this module is loaded via module-loader.sh" >&2
        exit 1
    fi
fi
```

### 3. Standalone Scripts (scripts/*.sh)
Standalone scripts should have a fallback `log()` function that uses `milou_log()` if available:

```bash
log() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        # Fallback for standalone execution
        local level="$1"
        shift
        local message="$*"
        case "$level" in
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
            "WARN") echo -e "${YELLOW}[WARN]${NC} $message" >&2 ;;
            "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
            *) echo "[INFO] $message" ;;
        esac
    fi
}
```

### 4. Main Script (milou.sh)
The main script has a simple fallback that attempts to use `milou_log()` if available:

```bash
log() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        # Simple fallback before modules are loaded
        local level="$1"
        shift
        local message="$*"
        case "$level" in
            "ERROR") echo "[ERROR] $message" >&2 ;;
            "WARN") echo "[WARN] $message" >&2 ;;
            "INFO") echo "[INFO] $message" ;;
            "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $message" ;;
            *) echo "[INFO] $message" ;;
        esac
    fi
}
```

## Log Levels

- **ERROR**: Critical errors that prevent operation
- **WARN**: Warnings that don't prevent operation but should be noted
- **INFO**: General information messages
- **SUCCESS**: Success confirmations with ✅ emoji
- **DEBUG**: Detailed information for troubleshooting (only shown in verbose mode)
- **TRACE**: Very detailed tracing information (only shown in debug mode)
- **STEP**: Major operation steps with ⚙️ emoji

## Benefits of Standardization

1. **Consistent Output**: All modules produce uniform log formatting
2. **Centralized Control**: Log levels, colors, and file output controlled from one place
3. **Easy Debugging**: Consistent debug and trace output patterns
4. **Better UX**: Emojis and colors for better visual feedback
5. **File Logging**: Automatic logging to files when configured

## Migration Complete

✅ **All duplicate logging functions have been removed**
✅ **All modules now use the standardized logging system**
✅ **Backward compatibility maintained through wrapper functions**
