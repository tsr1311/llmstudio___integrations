#!/bin/bash

# Script to update GitHub Issues when tasks are completed
# Usage: ./update-github-issues.sh <feature-directory>

set -e

FEATURE_DIR="$1"
if [ -z "$FEATURE_DIR" ]; then
    echo "Usage: $0 <feature-directory>"
    exit 1
fi

# Check for GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    exit 1
fi

# Get repository information
REPO_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos" | jq -r '.[] | select(.name == "llmstudio___integrations") | .full_name' | head -1)

if [ -z "$REPO_INFO" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ $REMOTE_URL == *"github.com"* ]]; then
        REPO_INFO=$(echo "$REMOTE_URL" | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
    else
        echo "Could not determine repository. Please set REPO_NAME environment variable."
        exit 1
    fi
fi

ISSUE_NUMBERS_FILE="$FEATURE_DIR/.issue_numbers"
if [ ! -f "$ISSUE_NUMBERS_FILE" ]; then
    echo "Issue numbers file not found: $ISSUE_NUMBERS_FILE"
    exit 1
fi

TASKS_FILE="$FEATURE_DIR/tasks.md"
if [ ! -f "$TASKS_FILE" ]; then
    echo "Tasks file not found: $TASKS_FILE"
    exit 1
fi

# Read issue numbers
mapfile -t ISSUE_NUMBERS < "$ISSUE_NUMBERS_FILE"

# Parse current task status
declare -A TASK_STATUS
LINE_NUM=1
while IFS= read -r line; do
    if [[ $line =~ ^- \[[ x]\] (.+)$ ]]; then
        TASK_TITLE="${BASH_REMATCH[1]}"
        if [[ $line == *"[x]"* ]]; then
            TASK_STATUS["$TASK_TITLE"]="completed"
        else
            TASK_STATUS["$TASK_TITLE"]="open"
        fi
    fi
    ((LINE_NUM++))
done < "$TASKS_FILE"

# Update issues based on task status
INDEX=0
for task in "${!TASK_STATUS[@]}"; do
    if [ $INDEX -lt ${#ISSUE_NUMBERS[@]} ]; then
        ISSUE_NUMBER="${ISSUE_NUMBERS[$INDEX]}"
        STATUS="${TASK_STATUS[$task]}"

        if [ "$STATUS" = "completed" ]; then
            # Close the issue
            curl -s -X PATCH \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"state\": \"closed\"}" \
                "https://api.github.com/repos/$REPO_INFO/issues/$ISSUE_NUMBER" > /dev/null

            echo "Closed issue #$ISSUE_NUMBER: $task"
        else
            # Ensure issue is open
            curl -s -X PATCH \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"state\": \"open\"}" \
                "https://api.github.com/repos/$REPO_INFO/issues/$ISSUE_NUMBER" > /dev/null

            echo "Ensured issue #$ISSUE_NUMBER is open: $task"
        fi
    fi
    ((INDEX++))
done

echo "Updated ${#TASK_STATUS[@]} issues"