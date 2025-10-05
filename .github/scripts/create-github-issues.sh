#!/bin/bash

# Script to create GitHub Issues from Spec Kit tasks
# Usage: ./create-github-issues.sh <feature-directory>

set -e

FEATURE_DIR="$1"
if [ -z "$FEATURE_DIR" ]; then
    echo "Usage: $0 <feature-directory>"
    exit 1
fi

# Check for GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    echo "Create a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo, issues"
    exit 1
fi

# Get repository information
REPO_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos" | jq -r '.[] | select(.name == "llmstudio___integrations") | .full_name' | head -1)

if [ -z "$REPO_INFO" ]; then
    # Try to get from git remote
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ $REMOTE_URL == *"github.com"* ]]; then
        REPO_INFO=$(echo "$REMOTE_URL" | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
    else
        echo "Could not determine repository. Please set REPO_NAME environment variable."
        exit 1
    fi
fi

echo "Creating issues for feature: $FEATURE_DIR"

# Read tasks from the feature directory
TASKS_FILE="$FEATURE_DIR/tasks.md"
if [ ! -f "$TASKS_FILE" ]; then
    echo "Tasks file not found: $TASKS_FILE"
    exit 1
fi

# Parse tasks and create issues
ISSUE_NUMBERS=()

while IFS= read -r line; do
    # Look for task headers (lines starting with - [ ])
    if [[ $line =~ ^- \[[ x]\] (.+)$ ]]; then
        TASK_TITLE="${BASH_REMATCH[1]}"

        # Create GitHub issue
        ISSUE_RESPONSE=$(curl -s -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"title\": \"$TASK_TITLE\", \"body\": \"Task from Spec Kit feature: $FEATURE_DIR\\n\\n**Status:** To Do\", \"labels\": [\"spec-kit\", \"task\"]}" \
            "https://api.github.com/repos/$REPO_INFO/issues")

        ISSUE_NUMBER=$(echo "$ISSUE_RESPONSE" | jq -r '.number')
        if [ "$ISSUE_NUMBER" != "null" ]; then
            ISSUE_NUMBERS+=("$ISSUE_NUMBER")
            echo "Created issue #$ISSUE_NUMBER: $TASK_TITLE"
        else
            echo "Failed to create issue for: $TASK_TITLE"
            echo "Response: $ISSUE_RESPONSE"
        fi
    fi
done < "$TASKS_FILE"

# Save issue numbers for tracking
if [ ${#ISSUE_NUMBERS[@]} -gt 0 ]; then
    echo "${ISSUE_NUMBERS[@]}" > "$FEATURE_DIR/.issue_numbers"
    echo "Issue numbers saved to: $FEATURE_DIR/.issue_numbers"
fi

echo "Created ${#ISSUE_NUMBERS[@]} issues"