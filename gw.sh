#!/usr/bin/env bash
# gw - Git Worktree Helper
# A flexible git worktree manager with configurable directory strategies
#
# Installation:
#   Source this file in your .zshrc or .bashrc:
#   source /path/to/gw.sh
#
# Usage:
#   gw create <name>     - Create a new worktree
#   gw rm <name>         - Remove a worktree
#   gw cd <name>         - Navigate to a worktree
#   gw list              - List all worktrees
#   gw config [strategy] - Get/set strategy for current repo
#   gw clean             - Remove all worktrees (with confirmation)

# Input validation function to prevent path traversal and command injection
_gw_validate_name() {
    local name="$1"

    # Check if name is empty
    if [[ -z "$name" ]]; then
        echo "Error: Worktree name cannot be empty" >&2
        return 1
    fi

    # Check length (max 255 characters)
    if [[ ${#name} -gt 255 ]]; then
        echo "Error: Worktree name too long (max 255 characters)" >&2
        return 1
    fi

    # Check for path traversal attempts
    if [[ "$name" == *".."* ]] || [[ "$name" == *"/"* ]] || [[ "$name" == *"\\"* ]]; then
        echo "Error: Invalid worktree name. Cannot contain '..', '/', or '\\'" >&2
        return 1
    fi

    # Check for valid characters (alphanumeric, dash, underscore, dot)
    if ! [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Error: Invalid worktree name. Use only letters, numbers, dots, dashes, and underscores" >&2
        return 1
    fi

    # Check for special names that could be problematic
    if [[ "$name" == "." ]] || [[ "$name" == ".." ]] || [[ "$name" == ".git" ]]; then
        echo "Error: Reserved name cannot be used" >&2
        return 1
    fi

    return 0
}

gw() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        _gw_usage
        return 0
    fi
    shift

    case "$cmd" in
        create)  _gw_create "$@" ;;
        rm|remove) _gw_remove "$@" ;;
        cd)      _gw_cd "$@" ;;
        list|ls) _gw_list "$@" ;;
        config)  _gw_config "$@" ;;
        clean)   _gw_clean "$@" ;;
        help|-h|--help) _gw_usage ;;
        *)       echo "Unknown command: $cmd"; _gw_usage; return 1 ;;
    esac
}

_gw_usage() {
    cat <<EOF
gw - Git Worktree Helper

Commands:
  create <name>                  Create a new worktree from current branch
  rm <name>                      Remove a worktree (with confirmation)
  cd <name>                      Navigate to a worktree
  list                           List all worktrees for current repo
  config [strategy]              Get/set worktree strategy for current repo
                                 Strategies: sibling (default), parent, global
  config --global [strategy]     Set global default strategy
  config --global-path <path>    Set base path for global strategy
  clean                          Remove all worktrees (with confirmation)

Examples:
  gw create feature-x       # Create worktree 'feature-x'
  gw cd feature-x           # Navigate to worktree
  gw config parent          # Use parent directory strategy
  gw config --global global # Set global strategy as default
  gw rm feature-x           # Remove worktree
EOF
}

# Get the git repository root
_gw_get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Get the repository name
_gw_get_repo_name() {
    local repo_root="$1"
    basename "$repo_root"
}

# Get configured strategy for current repo
_gw_get_strategy() {
    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && { echo "Not in a git repository"; return 1; }

    # Check repo-specific config first
    local repo_strategy
    repo_strategy=$(git config --get worktree.strategy 2>/dev/null)
    if [ -n "$repo_strategy" ]; then
        echo "$repo_strategy"
        return 0
    fi

    # Check for parent structure auto-detection
    if [ -d "$repo_root/../main" ] && [ -d "$repo_root/../worktrees" ]; then
        echo "parent"
        return 0
    fi

    # Check global config
    local global_strategy
    global_strategy=$(git config --global --get worktree.strategy 2>/dev/null)
    if [ -n "$global_strategy" ]; then
        echo "$global_strategy"
        return 0
    fi

    # Default to sibling
    echo "sibling"
}

# Get the base path for worktrees based on strategy
_gw_get_worktree_base() {
    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && return 1

    local repo_name
    repo_name="$(_gw_get_repo_name "$repo_root")"
    local strategy
    strategy="$(_gw_get_strategy)"

    case "$strategy" in
        sibling)
            echo "$(dirname "$repo_root")/${repo_name}-worktrees"
            ;;
        parent)
            # Assume we're in the main checkout
            local parent_dir
            parent_dir="$(dirname "$repo_root")"
            if [ "$(basename "$repo_root")" = "main" ]; then
                # We're already in parent structure
                echo "$parent_dir/worktrees"
            else
                # Need to create parent structure
                echo "${repo_root}-parent/worktrees"
            fi
            ;;
        global)
            local global_path
            global_path=$(git config --global --get worktree.globalPath 2>/dev/null)
            if [ -z "$global_path" ]; then
                global_path="$HOME/code/worktrees"
            fi
            echo "$global_path/$repo_name"
            ;;
        *)
            echo "Unknown strategy: $strategy" >&2
            return 1
            ;;
    esac
}

# Create a new worktree
_gw_create() {
    local name="$1"
    [ -z "$name" ] && { echo "Usage: gw create <name>"; return 1; }

    # Validate the worktree name
    if ! _gw_validate_name "$name"; then
        return 1
    fi

    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && { echo "Not in a git repository"; return 1; }

    local worktree_base
    worktree_base="$(_gw_get_worktree_base)"
    local worktree_path="$worktree_base/$name"

    # Check if worktree already exists (use fixed string matching)
    if git worktree list | grep -F -- "$worktree_path" > /dev/null 2>&1; then
        echo "Worktree '$name' already exists at $worktree_path"
        return 1
    fi

    # Get current branch
    local current_branch
    current_branch=$(git branch --show-current)
    if [ -z "$current_branch" ]; then
        echo "Warning: Not on a branch, using HEAD"
        current_branch="HEAD"
    fi

    # Create the worktree base directory if it doesn't exist
    if [ ! -d "$worktree_base" ]; then
        echo "Creating worktree base directory: $worktree_base"
        mkdir -p "$worktree_base"
    fi

    # Handle parent strategy special case
    local strategy
    strategy="$(_gw_get_strategy)"
    if [ "$strategy" = "parent" ] && [ "$(basename "$repo_root")" != "main" ]; then
        # Need to restructure to parent layout
        echo "Note: Converting to parent directory structure..."
        local parent_dir="${repo_root}-parent"
        local main_dir="$parent_dir/main"

        if [ ! -d "$parent_dir" ]; then
            mkdir -p "$parent_dir"
            echo "Moving current repo to $main_dir..."
            # This is tricky - we'd need to move the current repo
            echo "Warning: Manual intervention needed to convert to parent structure"
            echo "Please manually move your repo to: $main_dir"
            echo "Then run this command again from the new location"
            return 1
        fi
    fi

    # Create the worktree
    echo "Creating worktree '$name' at $worktree_path"
    echo "Based on branch: $current_branch"

    if ! git worktree add "$worktree_path" -b "$name" "$current_branch"; then
        echo "Failed to create worktree"
        return 1
    fi

    echo "Successfully created worktree '$name'"
    echo "To navigate to it, run: gw cd $name"
}

# Remove a worktree
_gw_remove() {
    local name="$1"
    [ -z "$name" ] && { echo "Usage: gw rm <name>"; return 1; }

    # Validate the worktree name
    if ! _gw_validate_name "$name"; then
        return 1
    fi

    local worktree_base
    worktree_base="$(_gw_get_worktree_base)"
    local worktree_path="$worktree_base/$name"

    # Check if worktree exists (use fixed string matching)
    if ! git worktree list | grep -F -- "$worktree_path" > /dev/null 2>&1; then
        echo "Worktree '$name' not found"
        return 1
    fi

    # Show what will be removed
    echo "This will remove the following worktree:"
    echo "  Path: $worktree_path"
    echo "  Branch: $name"
    echo
    printf "Are you sure you want to remove this worktree? [y/N] "
    read -r REPLY

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 1
    fi

    # Remove the worktree (try safe removal first, then force)
    if git worktree remove "$worktree_path" 2>/dev/null; then
        echo "Successfully removed worktree '$name'"

        # Also try to delete the branch if it exists and is not checked out
        if git show-ref --verify --quiet "refs/heads/$name"; then
            if git branch -d "$name" 2>/dev/null; then
                echo "Also deleted branch '$name'"
            else
                echo "Note: Branch '$name' still exists (may have unmerged changes)"
            fi
        fi
    elif git worktree remove --force "$worktree_path" 2>/dev/null; then
        echo "Warning: Forced removal of worktree (may have lost uncommitted changes)"
        echo "Successfully removed worktree '$name'"

        # Also try to delete the branch if it exists and is not checked out
        if git show-ref --verify --quiet "refs/heads/$name"; then
            if git branch -d "$name" 2>/dev/null; then
                echo "Also deleted branch '$name'"
            else
                echo "Note: Branch '$name' still exists (may have unmerged changes)"
            fi
        fi
    else
        echo "Failed to remove worktree. It may have uncommitted changes."
        echo "Use 'git worktree remove --force $worktree_path' to force removal."
        echo "WARNING: This will lose any uncommitted changes!"
        return 1
    fi
}

# Navigate to a worktree
_gw_cd() {
    local name="$1"
    [ -z "$name" ] && { echo "Usage: gw cd <name>"; return 1; }

    # Validate the worktree name
    if ! _gw_validate_name "$name"; then
        return 1
    fi

    local worktree_base
    worktree_base="$(_gw_get_worktree_base)"
    local worktree_path="$worktree_base/$name"

    if [ ! -d "$worktree_path" ]; then
        echo "Worktree '$name' not found at $worktree_path"
        echo "Available worktrees:"
        _gw_list
        return 1
    fi

    cd "$worktree_path" || return 1
    echo "Switched to worktree: $name"
    echo "Current directory: $(pwd)"
}

# List all worktrees for current repo
_gw_list() {
    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && { echo "Not in a git repository"; return 1; }

    local worktree_base
    worktree_base="$(_gw_get_worktree_base)"
    local strategy
    strategy="$(_gw_get_strategy)"

    echo "Worktree strategy: $strategy"
    echo "Worktree base: $worktree_base"
    echo
    echo "Worktrees:"

    # Use git worktree list and filter for our worktrees
    local found=false
    while IFS= read -r line; do
        # Use exact string matching to prevent pattern injection
        if echo "$line" | grep -F -- "$worktree_base" > /dev/null 2>&1 || echo "$line" | grep -F -- "$repo_root" > /dev/null 2>&1; then
            found=true
            # Extract path and branch from git worktree list output
            local wt_path="" wt_branch="" wt_name=""
            wt_path="${line%% *}"  # Get first word (path)
            wt_branch="${line##*\[}"  # Get part after last [
            wt_branch="${wt_branch%\]}"  # Remove trailing ]
            wt_name="${wt_path##*/}"  # Get basename

            if [ "$wt_path" = "$repo_root" ]; then
                echo "  * [main] $wt_path ($wt_branch)"
            else
                echo "  - $wt_name: $wt_path ($wt_branch)"
            fi
        fi
    done < <(git worktree list)

    if [ "$found" = false ]; then
        echo "  No worktrees found"
    fi
}

# Configure worktree strategy
_gw_config() {
    local arg="$1"

    # Handle global flags
    if [ "$arg" = "--global" ]; then
        shift
        local strategy="$1"
        if [ -z "$strategy" ]; then
            # Show global config
            local global_strategy
            global_strategy=$(git config --global --get worktree.strategy 2>/dev/null)
            local global_path
            global_path=$(git config --global --get worktree.globalPath 2>/dev/null)
            echo "Global worktree strategy: ${global_strategy:-sibling (default)}"
            if [ -n "$global_path" ]; then
                echo "Global worktree path: $global_path"
            fi
        else
            # Set global strategy
            if [[ "$strategy" =~ ^(sibling|parent|global)$ ]]; then
                git config --global worktree.strategy "$strategy"
                echo "Set global worktree strategy to: $strategy"
            else
                echo "Invalid strategy: $strategy"
                echo "Valid strategies: sibling, parent, global"
                return 1
            fi
        fi
        return 0
    fi

    if [ "$arg" = "--global-path" ]; then
        shift
        local path="$1"
        if [ -z "$path" ]; then
            echo "Usage: gw config --global-path <path>"
            return 1
        fi
        # Expand tilde safely
        path="${path/#\~/$HOME}"
        # Use realpath for safe path resolution (fallback to manual resolution)
        if command -v realpath >/dev/null 2>&1; then
            path=$(realpath -m "$path" 2>/dev/null) || { echo "Invalid path: $path"; return 1; }
        else
            # Manual safe path resolution
            local dir_part
            local base_part
            dir_part="$(dirname "$path")"
            base_part="$(basename "$path")"
            if [[ -d "$dir_part" ]]; then
                dir_part="$(cd "$dir_part" && pwd)" || { echo "Invalid path: $path"; return 1; }
            fi
            path="${dir_part}/${base_part}"
        fi
        git config --global worktree.globalPath "$path"
        echo "Set global worktree path to: $path"
        return 0
    fi

    # Repo-specific config
    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && { echo "Not in a git repository"; return 1; }

    if [ -z "$arg" ]; then
        # Show current config
        local strategy
        strategy="$(_gw_get_strategy)"
        local repo_config
        repo_config=$(git config --get worktree.strategy 2>/dev/null)

        echo "Current worktree strategy: $strategy"
        if [ -n "$repo_config" ]; then
            echo "  (set in repo config)"
        else
            echo "  (using ${strategy} default)"
        fi

        echo
        echo "Worktree base directory: $(_gw_get_worktree_base)"
    else
        # Set strategy
        if [[ "$arg" =~ ^(sibling|parent|global)$ ]]; then
            # Check for existing worktrees
            local worktree_count
            worktree_count=$(git worktree list | wc -l)
            if [ "$worktree_count" -gt 1 ]; then
                echo "Warning: Changing strategy with existing worktrees may orphan them."
                printf "Continue? [y/N] "
                read -r REPLY
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Cancelled"
                    return 1
                fi
            fi

            git config worktree.strategy "$arg"
            echo "Set worktree strategy to: $arg"
            echo "New worktree base: $(_gw_get_worktree_base)"
        else
            echo "Invalid strategy: $arg"
            echo "Valid strategies: sibling, parent, global"
            return 1
        fi
    fi
}

# Clean all worktrees
_gw_clean() {
    local repo_root
    repo_root="$(_gw_get_repo_root)"
    [ -z "$repo_root" ] && { echo "Not in a git repository"; return 1; }

    local worktree_base
    worktree_base="$(_gw_get_worktree_base)"

    echo "WARNING: This will remove ALL worktrees for this repository!"
    echo "Worktrees to be removed:"

    local count=0
    while IFS= read -r line; do
        local path
        path=$(echo "$line" | awk '{print $1}')
        # Skip the main repository
        if [ "$path" = "$repo_root" ]; then
            continue
        fi
        # Check if this worktree is in our worktree base
        if echo "$path" | grep -F -- "$worktree_base" > /dev/null 2>&1; then
            local branch
            branch=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
            echo "  - $path ($branch)"
            count=$((count + 1))
        fi
    done < <(git worktree list)

    if [ "$count" -eq 0 ]; then
        echo "No worktrees to remove"
        return 0
    fi

    echo
    echo "This action cannot be undone!"
    printf "Type 'yes' to confirm: "
    read -r REPLY

    if [ "$REPLY" != "yes" ]; then
        echo "Cancelled"
        return 1
    fi

    # Remove all worktrees
    while IFS= read -r line; do
        local path
        path=$(echo "$line" | awk '{print $1}')
        # Skip the main repository
        if [ "$path" = "$repo_root" ]; then
            continue
        fi
        # Check if this worktree is in our worktree base
        if echo "$path" | grep -F -- "$worktree_base" > /dev/null 2>&1; then
            echo "Removing: $path"
            # Try safe removal first
            if ! git worktree remove "$path" 2>/dev/null; then
                echo "  Warning: Using force removal for $path"
                git worktree remove --force "$path" 2>/dev/null
            fi
        fi
    done < <(git worktree list)

    echo "All worktrees removed"

    # Try to remove the worktree base directory if empty
    if [ -d "$worktree_base" ] && [ -z "$(ls -A "$worktree_base")" ]; then
        rmdir "$worktree_base" 2>/dev/null && echo "Removed empty worktree base directory"
    fi
}

# Bash/Zsh completion for gw
if [ -n "${BASH_VERSION:-}" ]; then
    _gw_complete() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local cmd="${COMP_WORDS[1]}"

        if [ "$COMP_CWORD" -eq 1 ]; then
            # Use readarray if available, otherwise fall back to direct assignment
            if command -v mapfile >/dev/null 2>&1; then
                mapfile -t COMPREPLY < <(compgen -W "create rm remove cd list ls config clean help" -- "$cur")
            else
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "create rm remove cd list ls config clean help" -- "$cur"))
            fi
        elif [ "$cmd" = "config" ] && [ "$COMP_CWORD" -eq 2 ]; then
            if command -v mapfile >/dev/null 2>&1; then
                mapfile -t COMPREPLY < <(compgen -W "sibling parent global --global --global-path" -- "$cur")
            else
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "sibling parent global --global --global-path" -- "$cur"))
            fi
        elif [[ "$cmd" =~ ^(rm|remove|cd)$ ]] && [ "$COMP_CWORD" -eq 2 ]; then
            # Complete with worktree names (safely handle special characters)
            local worktree_base
            worktree_base="$(_gw_get_worktree_base 2>/dev/null)"
            if [ -n "$worktree_base" ] && [ -d "$worktree_base" ]; then
                local names
                names=$(ls "$worktree_base" 2>/dev/null | tr '\n' ' ')
                if command -v mapfile >/dev/null 2>&1; then
                    mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
                else
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "$names" -- "$cur"))
                fi
            fi
        fi
    }
    complete -F _gw_complete gw

elif [ -n "${ZSH_VERSION:-}" ]; then
    # Only set up completion if we're in an interactive shell with completion system
    if [[ -o interactive ]] && command -v compdef &>/dev/null 2>&1; then
        _gw_complete() {
            # These variables are set by ZSH completion system
            # shellcheck disable=SC2034,SC2154
            local -a commands worktree_names strategies

            # shellcheck disable=SC2034  # Used by _describe function below
            commands=(
                'create:Create a new worktree'
                'rm:Remove a worktree'
                'remove:Remove a worktree'
                'cd:Navigate to a worktree'
                'list:List all worktrees'
                'ls:List all worktrees'
                'config:Configure worktree strategy'
                'clean:Remove all worktrees'
                'help:Show help'
            )

            # shellcheck disable=SC2034  # Used by _describe function below
            strategies=(
                'sibling:Use sibling directory strategy'
                'parent:Use parent directory strategy'
                'global:Use global directory strategy'
                '--global:Set global default'
                '--global-path:Set global base path'
            )

            # shellcheck disable=SC2154  # 'words' is set by ZSH completion system
            case "${words[2]}" in
                config)
                    if [ "$CURRENT" -eq 3 ]; then
                        _describe 'strategy' strategies
                    fi
                    ;;
                rm|remove|cd)
                    if [ "$CURRENT" -eq 3 ]; then
                        local worktree_base
                        worktree_base="$(_gw_get_worktree_base 2>/dev/null)"
                        if [ -n "$worktree_base" ] && [ -d "$worktree_base" ]; then
                            # Safely populate array
                            worktree_names=()
                            while IFS= read -r name; do
                                worktree_names+=("$name")
                            done < <(ls "$worktree_base" 2>/dev/null)
                            _describe 'worktree' worktree_names
                        fi
                    fi
                    ;;
                *)
                    if [ "$CURRENT" -eq 2 ]; then
                        _describe 'command' commands
                    fi
                    ;;
            esac
        }

        compdef _gw_complete gw 2>/dev/null
    fi
fi

# Return success
return 0 2>/dev/null || true
