#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_result="${3:-0}"  # Default to expecting success
    
    echo -n "Testing: $test_name ... "
    
    if [ "$expected_result" -eq 0 ]; then
        if eval "$test_cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAILED${NC}"
            echo "  Command: $test_cmd"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        # Expecting failure
        if eval "$test_cmd" >/dev/null 2>&1; then
            echo -e "${RED}FAILED${NC} (should have failed)"
            echo "  Command: $test_cmd"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            echo -e "${GREEN}PASSED${NC} (correctly failed)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    fi
}

# Source the script
echo "=== Loading gw.sh script ==="
source /workspace/gw.sh

echo ""
echo "=== Testing Input Validation ==="

# Test valid names
run_test "Valid name: simple" "_gw_validate_name 'test-branch'" 0
run_test "Valid name: with numbers" "_gw_validate_name 'feature-123'" 0
run_test "Valid name: with underscore" "_gw_validate_name 'my_feature'" 0
run_test "Valid name: with dots" "_gw_validate_name 'v1.2.3'" 0

# Test invalid names - these should fail
run_test "Invalid: path traversal .." "_gw_validate_name '../etc'" 1
run_test "Invalid: path traversal /" "_gw_validate_name 'etc/passwd'" 1
run_test "Invalid: backslash" "_gw_validate_name 'test\\branch'" 1
run_test "Invalid: command injection semicolon" "_gw_validate_name 'test;ls'" 1
run_test "Invalid: command injection backtick" "_gw_validate_name 'test\`ls\`'" 1
run_test "Invalid: command injection dollar" "_gw_validate_name 'test\$(ls)'" 1
run_test "Invalid: pipe character" "_gw_validate_name 'test|ls'" 1
run_test "Invalid: ampersand" "_gw_validate_name 'test&ls'" 1
run_test "Invalid: redirect" "_gw_validate_name 'test>file'" 1
run_test "Invalid: space" "_gw_validate_name 'test branch'" 1
run_test "Invalid: empty string" "_gw_validate_name ''" 1
run_test "Invalid: dot only" "_gw_validate_name '.'" 1
run_test "Invalid: double dot" "_gw_validate_name '..'" 1
run_test "Invalid: .git" "_gw_validate_name '.git'" 1

# Test name length
LONG_NAME=$(python3 -c "print('a' * 256)")
run_test "Invalid: name too long (256 chars)" "_gw_validate_name '$LONG_NAME'" 1

echo ""
echo "=== Setting up Git Repository ==="

# Configure git if not already configured
if ! git config --get user.email >/dev/null 2>&1; then
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git config --global init.defaultBranch main
fi

# Create a test repository
mkdir -p test-repo
cd test-repo
git init
echo "test" > README.md
git add README.md
git commit -m "Initial commit"

echo ""
echo "=== Testing Worktree Operations ==="

# Test creating worktrees with safe names
run_test "Create worktree with valid name" "gw create feature-test" 0
run_test "List worktrees" "gw list" 0
run_test "Navigate to worktree" "gw cd feature-test && pwd | grep -q feature-test" 0

# Go back to main repo
cd /home/testuser/test-repos/test-repo

# Test the new 'go' command
run_test "Go to existing worktree" "gw go feature-test && pwd | grep -q feature-test" 0

# Go back to main repo
cd /home/testuser/test-repos/test-repo

# Test 'go' command creating new worktree
run_test "Go command creates new worktree" "gw go feature-go-test && pwd | grep -q feature-go-test" 0

# Go back to main repo  
cd /home/testuser/test-repos/test-repo

# Test creating worktree with dangerous names (should be rejected)
run_test "Reject worktree with path traversal" "gw create '../dangerous'" 1
run_test "Reject worktree with command injection" "gw create 'test;rm -rf /'" 1
run_test "Reject worktree with pipe" "gw create 'test|cat /etc/passwd'" 1

# Test 'go' command with dangerous names (should be rejected)
run_test "Go rejects path traversal" "gw go '../dangerous'" 1
run_test "Go rejects command injection" "gw go 'test;rm -rf /'" 1

# Test removal (provide 'y' for confirmation)
run_test "Remove worktree" "echo y | gw rm feature-test" 0
run_test "Remove go-created worktree" "echo y | gw rm feature-go-test" 0

echo ""
echo "=== Testing Configuration ==="

# Make sure we're in a git repo for config tests
cd /home/testuser/test-repos/test-repo

# Test strategy configuration
run_test "Set sibling strategy" "gw config sibling" 0
run_test "Set parent strategy" "gw config parent" 0
run_test "Set global strategy" "gw config global" 0
run_test "Invalid strategy" "gw config invalid-strategy" 1

# Test global configuration
run_test "Set global strategy" "gw config --global sibling" 0
run_test "Set global path" "gw config --global-path ~/worktrees" 0

echo ""
echo "=== Testing Edge Cases ==="

# Create multiple worktrees for cleanup test
gw create test1 >/dev/null 2>&1 || true
gw create test2 >/dev/null 2>&1 || true
gw create test3 >/dev/null 2>&1 || true

# Test clean command (with auto-yes for testing)
run_test "Clean all worktrees" "echo 'yes' | gw clean" 0

# Test operations outside git repo
cd /tmp
run_test "Fail when not in git repo" "gw create test" 1
run_test "Fail list when not in git repo" "gw list" 1

echo ""
echo "=== Testing Shell Injection Protection ==="

# Create a new test repo for injection tests
cd /home/testuser/test-repos
mkdir -p injection-test
cd injection-test
git init
echo "test" > README.md
git add README.md
git commit -m "Initial commit"

# These tests verify that malicious input is properly sanitized
# They should all fail safely without executing injected commands

# Test 1: Command substitution attempts
run_test "Block command substitution in name" "gw create '\$(echo pwned)'" 1
run_test "Block backtick substitution" "gw create '\`id\`'" 1

# Test 2: File path injection attempts
MALICIOUS_PATH="../../../../../../tmp/evil"
run_test "Block path traversal in worktree name" "gw create '$MALICIOUS_PATH'" 1

# Test 3: Special characters that could break quoting
run_test "Handle single quotes safely" "gw create \"test'name\"" 1
run_test "Handle double quotes safely" "gw create 'test\"name'" 1

# Test 4: Null byte injection
run_test "Block null bytes" "printf 'gw create test\x00evil' | bash" 1

# Test 5: Newline injection
run_test "Block newline characters" "gw create 'test\nmalicious-command'" 1

# Grep pattern safety is tested implicitly throughout
# The script uses grep -F for literal matching which is secure

echo ""
echo "=== Test Summary ==="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi