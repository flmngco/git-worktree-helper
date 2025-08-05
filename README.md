# Git Worktree Helper (gw)

A powerful and flexible git worktree management tool that simplifies working with multiple branches simultaneously. Inspired by the workflow described in [Claude Code's documentation](https://docs.anthropic.com/en/docs/claude-code/common-workflows#run-parallel-claude-code-sessions-with-git-worktrees), this tool makes git worktrees as easy to use as regular branches.

## Why Git Worktrees?

Git worktrees are a game-changer for parallel development. Unlike regular branches where you need to stash changes and switch contexts, worktrees give you **multiple working directories** for the same repository - each on a different branch. This means:

- **Instant context switching** - Just `cd` to another directory
- **No stashing required** - Keep all your work-in-progress
- **Parallel testing** - Run different versions simultaneously
- **Quick hotfixes** - Fix production issues without disrupting feature work
- **Multiple Claude Code sessions** - Run AI assistance on different features in parallel

## Features

- **Three directory strategies** - Choose how worktrees are organized:
  - **Sibling** (default): `repo/../repo-worktrees/feature`
  - **Parent**: `repo-parent/main/` and `repo-parent/worktrees/feature`
  - **Global**: `~/code/worktrees/repo-feature`
- **Per-repo configuration** - Different strategies for different projects
- **Safety first** - Confirmations for destructive operations
- **Shell completion** - Tab completion for Bash and Zsh

## Installation

### Option 1: Direct Download
```bash
# Download the script
curl -o ~/.local/bin/gw.sh https://raw.githubusercontent.com/flmngco/git-worktree-helper/main/gw.sh

# Source it in your shell configuration
echo 'source ~/.local/bin/gw.sh' >> ~/.zshrc  # or ~/.bashrc

# Reload your shell
source ~/.zshrc  # or ~/.bashrc
```

### Option 2: Clone Repository
```bash
# Clone the repository
git clone https://github.com/flmngco/git-worktree-helper.git ~/git-worktree-helper

# Source it in your shell configuration
echo 'source ~/git-worktree-helper/gw.sh' >> ~/.zshrc  # or ~/.bashrc

# Reload your shell
source ~/.zshrc  # or ~/.bashrc
```

## Quick Start

### Basic Workflow
```bash
# You're on main branch, need to work on a new feature
gw create feature-auth       # Creates worktree with new branch 'feature-auth'
gw cd feature-auth           # Jump into the worktree
# ... make changes, commit ...

# Suddenly need to fix a bug in production
cd -                         # Back to main
gw create hotfix-login       # Create hotfix worktree
gw cd hotfix-login          # Jump to hotfix
# ... fix bug, commit, push ...

# Continue feature work without losing context
gw cd feature-auth          # Back to feature instantly
# ... continue development ...

# See all your worktrees
gw list

# Clean up when done
gw rm hotfix-login          # Remove hotfix worktree
gw rm feature-auth          # Remove feature worktree
```

### Parallel Development
```bash
# Terminal 1: Work on authentication feature
gw create feature-auth
gw cd feature-auth

# Terminal 2: Work on database refactoring
gw create refactor-db
gw cd refactor-db

# Terminal 3: Fix a critical bug
gw create bugfix-memory-leak
gw cd bugfix-memory-leak
```

## Commands

### `gw create <name>`
Creates a new worktree based on the current branch. The worktree will be created with a new branch named `<name>`.

```bash
gw create new-feature
# Creates worktree at ../repo-worktrees/new-feature (default sibling strategy)
# Creates new branch 'new-feature' based on current branch
```

### `gw cd <name>`
Navigate to an existing worktree.

```bash
gw cd new-feature
# Changes directory to the worktree
```

### `gw list`
Shows all worktrees for the current repository.

```bash
gw list
# Output:
# Worktree strategy: sibling
# Worktree base: /Users/you/projects/myrepo-worktrees
#
# Worktrees:
#   * [main] /Users/you/projects/myrepo (main)
#   - feature-a: /Users/you/projects/myrepo-worktrees/feature-a (feature-a)
#   - bugfix: /Users/you/projects/myrepo-worktrees/bugfix (bugfix)
```

### `gw rm <name>`
Removes a worktree with confirmation prompt.

```bash
gw rm old-feature
# Shows what will be removed and asks for confirmation
# Also attempts to delete the associated branch
```

### `gw config [strategy]`
Configure the worktree strategy for the current repository.

```bash
# Show current configuration
gw config

# Set repository to use parent strategy
gw config parent

# Set repository to use global strategy
gw config global

# Set repository back to sibling strategy
gw config sibling
```

### `gw config --global [strategy]`
Set the global default strategy.

```bash
# Show global configuration
gw config --global

# Set global default to global strategy
gw config --global global
```

### `gw config --global-path <path>`
Set the base path for the global strategy.

```bash
# Set custom path for global worktrees
gw config --global-path ~/projects/worktrees
```

### `gw clean`
Remove all worktrees for the current repository (with strong confirmation).

```bash
gw clean
# Lists all worktrees that will be removed
# Requires typing 'yes' to confirm
```

## Directory Strategies Explained

The tool offers three different strategies for organizing your worktrees. Each has its own advantages depending on your workflow and preferences.

### Sibling Strategy (Default)

Worktrees live alongside your main repository as siblings in the parent directory:

```
~/projects/
├── myrepo/                  # Your main repository
└── myrepo-worktrees/        # All worktrees for this repo
    ├── feature-auth/
    ├── feature-payments/
    └── bugfix-header/
```

**How it works:**
- Creates a `-worktrees` directory next to your repo
- Each worktree is isolated from the main repository
- Clean separation prevents git confusion

**Pros:**
- Zero configuration needed - works out of the box
- Worktrees are easy to find (right next to your repo)
- No git plumbing issues or tool confusion
- Easy to identify which worktrees belong to which repo

**Cons:**
- Clutters the parent directory if you have many repos
- Worktrees and repo can get separated if moved individually

**Best for:** Most users. This is the recommended default because it "just works" without any setup or planning.

**Example workflow:**
```bash
cd ~/projects/myrepo
gw create feature-new    # Creates ~/projects/myrepo-worktrees/feature-new
```

### Parent Strategy

Creates a parent container that holds both your main repository and all its worktrees:

```
~/projects/myrepo-parent/    # Container directory
├── main/                    # Your main repository (renamed)
└── worktrees/              # All worktrees
    ├── feature-auth/
    ├── feature-payments/
    └── bugfix-header/
```

**How it works:**
- Everything related to the project lives in one parent directory
- Main repo typically lives in a `main/` subdirectory
- All worktrees grouped in `worktrees/` subdirectory

**Pros:**
- Everything is self-contained in one directory
- Easy to archive, backup, or move the entire project
- Clear organizational hierarchy
- Can zip/tar the entire project with all branches

**Cons:**
- Requires restructuring existing repos (move to `main/` subdirectory)
- Initial setup is more complex
- Tools expecting repo at root level might need reconfiguration

**Best for:** New projects where you can structure from the start, or projects you want to keep completely self-contained.

**Migration example:**
```bash
# Starting with: ~/projects/myrepo
mv ~/projects/myrepo ~/projects/myrepo-parent/main
cd ~/projects/myrepo-parent/main
gw config parent
gw create feature-new    # Creates ~/projects/myrepo-parent/worktrees/feature-new
```

### Global Strategy

All worktrees from all repositories collected in one global location:

```
~/code/worktrees/           # Global worktrees directory
├── myrepo-feature-auth/
├── myrepo-bugfix-header/
├── other-repo-feature-x/
├── third-repo-experiment/
└── another-repo-refactor/
```

**How it works:**
- Configure a global directory for ALL worktrees
- Worktrees from different repos all live in the same place
- Main repositories stay in their original locations

**Pros:**
- Single place to see all active work across all projects
- Main repos remain untouched in their original locations
- Great for "inbox zero" approach - see all WIP at a glance
- Easy cleanup of old worktrees (just check one directory)

**Cons:**
- Worktrees separated from their main repositories
- Can get cluttered with many active projects
- Need to remember which worktree belongs to which repo

**Best for:** Power users working on many repositories who want a dedicated "workspace" area separate from their main code organization.

**Setup example:**
```bash
# Configure globally for all repos
gw config --global global
gw config --global-path ~/workspace/active

# Or per-repository
cd ~/projects/myrepo
gw config global
gw create feature-new    # Creates ~/workspace/active/myrepo-feature-new
```

### Choosing the Right Strategy

| If you... | Choose... | Why |
|-----------|-----------|-----|
| Want it to just work | **Sibling** | No configuration, no surprises |
| Are starting a new project | **Parent** | Design for organization from the start |
| Work on many repos simultaneously | **Global** | See all your WIP in one place |
| Share repos with a team | **Sibling** | Others won't be confused by your structure |
| Want portable project archives | **Parent** | Everything in one directory to zip/move |
| Like separation of concerns | **Global** | Worktrees separate from source code |

### Strategy Comparison

| Feature | Sibling | Parent | Global |
|---------|---------|--------|--------|
| **Setup complexity** | None | Medium | Low |
| **Organization** | Next to repo | Self-contained | Centralized |
| **Best for teams** | ✅ Yes | ⚠️ Maybe | ❌ No |
| **Portability** | Medium | ✅ High | Low |
| **Scales to many repos** | ⚠️ Okay | ⚠️ Okay | ✅ Great |
| **Risk of confusion** | Low | Medium | Low |

## Configuration Examples

### Per-Repository Setup
```bash
# Repository A: Use sibling strategy (default)
cd ~/projects/repo-a
gw config sibling

# Repository B: Use parent strategy
cd ~/projects/repo-b
gw config parent

# Repository C: Use global strategy
cd ~/projects/repo-c
gw config global
```

### Global Configuration
```bash
# Set global default to use global strategy
gw config --global global

# Set custom global worktrees path
gw config --global-path ~/workspace/trees

# Now all repos without specific config will use global strategy
```

## Shell Completion

Tab completion is automatically enabled for both Bash and Zsh:

```bash
gw <TAB>           # Shows all commands
gw cd <TAB>        # Shows all worktree names
gw rm <TAB>        # Shows all worktree names
gw config <TAB>    # Shows strategy options
```

## Tips and Tricks

### Quick Feature Development
```bash
# Start new feature
gw create feature-awesome
gw cd feature-awesome
# ... develop feature ...

# Switch back to main
cd -

# Clean up when merged
gw rm feature-awesome
```

### Parallel Development
```bash
# Work on multiple features simultaneously
gw create feature-1 && gw cd feature-1  # Terminal 1
gw create feature-2 && gw cd feature-2  # Terminal 2
gw create bugfix-1 && gw cd bugfix-1    # Terminal 3
```

### Check Before Switching Strategy
```bash
# See current setup before changing
gw list
gw config

# Change strategy
gw config parent

# Verify new configuration
gw config
```

## Troubleshooting

### "Not in a git repository"
Make sure you're inside a git repository when running gw commands.

### Worktree already exists
Check `gw list` to see existing worktrees. Remove the old one with `gw rm <name>` if needed.

### Cannot remove worktree
The worktree may have uncommitted changes. Either commit/stash changes or use:
```bash
git worktree remove --force <path>
```

### Strategy change warning
Changing strategies with existing worktrees may orphan them. Consider using `gw clean` before switching strategies, or manually managing the transition.

## Git Worktree Basics

Git worktrees allow you to have multiple working directories for the same repository, each on a different branch:

- **No stashing needed** - Keep work-in-progress on multiple features
- **Parallel development** - Work on hotfix while keeping feature branch open
- **Fast switching** - No need to checkout, just `cd` to another worktree
- **Isolated changes** - Each worktree has its own working directory and index

Learn more: [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)

## Testing

The project includes security and functionality tests that run in isolated Docker containers.

### Running Tests Locally

```bash
# Build and run the test container
docker build -t gw-test .
docker run --rm gw-test

# Run tests with your local changes
docker run --rm -v $(pwd)/gw.sh:/workspace/gw.sh:ro gw-test
```

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit issues and pull requests.
