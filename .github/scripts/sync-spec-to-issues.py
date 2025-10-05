#!/usr/bin/env python3

import os
import sys
import re
from pathlib import Path
from github import Github
import requests

def get_repo_info():
    """Get repository information from environment or git remote"""
    repo_name = os.getenv('REPO_NAME', os.getenv('GITHUB_REPOSITORY'))
    if not repo_name:
        # Try to get from git remote
        try:
            import subprocess
            result = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                                  capture_output=True, text=True, check=True)
            url = result.stdout.strip()
            if 'github.com' in url:
                repo_name = url.split('github.com/')[1].replace('.git', '')
        except:
            pass

    if not repo_name:
        raise ValueError("Could not determine repository name. Set REPO_NAME environment variable.")

    return repo_name

def parse_tasks_file(tasks_file):
    """Parse tasks.md file and return list of tasks with status"""
    tasks = []
    with open(tasks_file, 'r') as f:
        for line in f:
            # Match task lines: - [ ] Task title or - [x] Task title
            match = re.match(r'- \[([ x])\] (.+)', line.strip())
            if match:
                status = 'completed' if match.group(1) == 'x' else 'open'
                title = match.group(2)
                tasks.append({'title': title, 'status': status})
    return tasks

def create_or_update_issue(g, repo_name, feature_dir, task_title, task_status, existing_issues):
    """Create or update GitHub issue for a task"""
    repo = g.get_repo(repo_name)

    # Check if issue already exists
    issue_title = f"[Spec Kit] {task_title}"
    existing_issue = None

    for issue in existing_issues:
        if issue.title == issue_title:
            existing_issue = issue
            break

    body = f"""Task from Spec Kit feature: `{feature_dir}`

**Status:** {task_status.title()}
**Feature:** {feature_dir}

This issue was automatically created from Spec Kit task breakdown.
"""

    if existing_issue:
        # Update existing issue
        if task_status == 'completed' and existing_issue.state == 'open':
            existing_issue.edit(state='closed', body=body)
            print(f"Closed issue #{existing_issue.number}: {task_title}")
        elif task_status == 'open' and existing_issue.state == 'closed':
            existing_issue.edit(state='open', body=body)
            print(f"Reopened issue #{existing_issue.number}: {task_title}")
        else:
            existing_issue.edit(body=body)
            print(f"Updated issue #{existing_issue.number}: {task_title}")
        return existing_issue.number
    else:
        # Create new issue
        issue = repo.create_issue(
            title=issue_title,
            body=body,
            labels=['spec-kit', 'auto-generated', f"status:{task_status}"]
        )
        print(f"Created issue #{issue.number}: {task_title}")
        return issue.number

def main():
    # Get GitHub token
    token = os.getenv('GITHUB_TOKEN')
    if not token:
        print("Error: GITHUB_TOKEN environment variable not set")
        sys.exit(1)

    # Initialize GitHub client
    g = Github(token)

    # Get repository info
    repo_name = get_repo_info()
    print(f"Working with repository: {repo_name}")

    # Get feature directory from command line or find all
    if len(sys.argv) > 1:
        feature_dirs = [sys.argv[1]]
    else:
        # Find all feature directories
        specs_dir = Path('specs')
        if specs_dir.exists():
            feature_dirs = [str(d) for d in specs_dir.iterdir() if d.is_dir()]
        else:
            print("No specs directory found")
            sys.exit(1)

    # Get existing issues to avoid duplicates
    repo = g.get_repo(repo_name)
    existing_issues = list(repo.get_issues(state='all', labels=['spec-kit']))

    total_created = 0
    total_updated = 0

    for feature_dir in feature_dirs:
        tasks_file = Path(feature_dir) / 'tasks.md'
        if not tasks_file.exists():
            print(f"No tasks.md found in {feature_dir}, skipping")
            continue

        print(f"Processing feature: {feature_dir}")

        # Parse tasks
        tasks = parse_tasks_file(tasks_file)

        # Create/update issues
        for task in tasks:
            issue_num = create_or_update_issue(g, repo_name, feature_dir,
                                             task['title'], task['status'],
                                             existing_issues)
            if issue_num:
                total_created += 1

    print(f"Processed {total_created} issues across {len(feature_dirs)} features")

if __name__ == '__main__':
    main()