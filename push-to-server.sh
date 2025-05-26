#!/bin/bash

DEFAULT_IP="147.182.179.32"
REMOTE_IP=${1:-$DEFAULT_IP}
SERVER_SSH_KEY="$HOME/.ssh/digitalocean" # For connecting to the server

# === milou_fresh (milou.git) Configuration ===
MF_LOCAL_DIR="$HOME/milou_fresh" # Used for local existence check
MF_REMOTE_DIR="/home/milou_fresh"
MF_GIT_URL="git@github.com:milou-sh/milou.git"
MF_GIT_BRANCH="dev-milou-cli-fix"
MF_PROJECT_NAME="milou_fresh (milou.git)"

# === milou-cli Configuration ===
MC_LOCAL_DIR="$HOME/milou-cli" # Used for local existence check
MC_REMOTE_DIR="/home/milou-cli"
MC_GIT_URL="git@github.com:milou-sh/milou-cli.git"
MC_GIT_BRANCH="dev"
MC_PROJECT_NAME="milou-cli"

# === GitHub SSH Key for Server ===
GITHUB_SSH_KEY_LOCAL="$HOME/.ssh/github"
GITHUB_SSH_KEY_REMOTE_PATH="/root/.ssh/github" # Key path on the remote server

# Ensure DigitalOcean private key exists
if [ ! -f "$SERVER_SSH_KEY" ]; then
  echo "❌ SSH key for server access not found at $SERVER_SSH_KEY"
  exit 1
fi
chmod 600 "$SERVER_SSH_KEY" # Set permissions for the connection key

# --- Deploy GitHub SSH Key to Server ---
if [ -f "$GITHUB_SSH_KEY_LOCAL" ]; then
  echo "🔑 Deploying GitHub SSH key to $REMOTE_IP..."
  ssh -i "$SERVER_SSH_KEY" root@"$REMOTE_IP" "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
  scp -i "$SERVER_SSH_KEY" "$GITHUB_SSH_KEY_LOCAL" root@"$REMOTE_IP":"$GITHUB_SSH_KEY_REMOTE_PATH"
  ssh -i "$SERVER_SSH_KEY" root@"$REMOTE_IP" "chmod 600 $GITHUB_SSH_KEY_REMOTE_PATH"
  echo "✅ GitHub SSH key deployed to $GITHUB_SSH_KEY_REMOTE_PATH and permissions set."
else
  echo "⚠️ GitHub SSH key not found locally at $GITHUB_SSH_KEY_LOCAL. Git operations on the server might fail if the key is not already present."
fi

# Ensure local project directories exist (optional check, but good practice)
if [ ! -d "$MF_LOCAL_DIR" ]; then
  echo "⚠️ Local directory not found: $MF_LOCAL_DIR (This script primarily deploys from GitHub)"
fi
if [ ! -d "$MC_LOCAL_DIR" ]; then
  echo "⚠️ Local directory not found: $MC_LOCAL_DIR (This script primarily deploys from GitHub)"
fi

# --- Ensure git is installed on remote and deploy/update repositories ---
echo "📦 Ensuring git is installed on remote $REMOTE_IP and managing repositories..."
ssh -i "$SERVER_SSH_KEY" root@"$REMOTE_IP" bash -s -- \
  "$(printf "%q" "$MF_GIT_URL")" \
  "$(printf "%q" "$MF_GIT_BRANCH")" \
  "$(printf "%q" "$MF_REMOTE_DIR")" \
  "$(printf "%q" "$MF_PROJECT_NAME")" \
  "$(printf "%q" "$MC_GIT_URL")" \
  "$(printf "%q" "$MC_GIT_BRANCH")" \
  "$(printf "%q" "$MC_REMOTE_DIR")" \
  "$(printf "%q" "$MC_PROJECT_NAME")" \
  "$(printf "%q" "$GITHUB_SSH_KEY_REMOTE_PATH")" \
<< 'EOF_REMOTE_SCRIPT'

  # Arguments from the local script
  MF_GIT_URL="$1"
  MF_GIT_BRANCH="$2"
  MF_REMOTE_DIR="$3"
  MF_PROJECT_NAME="$4"
  MC_GIT_URL="$5"
  MC_GIT_BRANCH="$6"
  MC_REMOTE_DIR="$7"
  MC_PROJECT_NAME="$8"
  GITHUB_KEY="$9"

  # Ensure git is installed
  if ! command -v git &> /dev/null; then
    echo "git could not be found on the server. Installing git..."
    apt-get update && apt-get install -y git
    if ! command -v git &> /dev/null; then
      echo "❌ Failed to install git on the server. Exiting."
      exit 1
    fi
  fi

  # Function to manage a git repository (clone or pull)
  manage_repo() {
    local git_url="$1"
    local branch="$2"
    local remote_dir="$3"
    local project_name="$4"
    local git_ssh_command="GIT_SSH_COMMAND=\"ssh -i $GITHUB_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no\""

    echo "-----------------------------------------------------"
    echo "🔄 Managing $project_name repository in $remote_dir on branch $branch..."

    # Ensure parent directory of remote_dir exists
    local parent_dir
    parent_dir=$(dirname "$remote_dir")
    if ! mkdir -p "$parent_dir"; then
        echo "❌ Failed to create parent directory $parent_dir for $project_name."
        return 1
    fi

    if [ -d "$remote_dir/.git" ]; then
      echo "Found existing $project_name repository. Updating..."
      cd "$remote_dir" || { echo "❌ Failed to cd into $remote_dir"; return 1; }

      current_branch=$(git rev-parse --abbrev-ref HEAD)
      echo "Current branch is $current_branch."

      if [ "$current_branch" != "$branch" ]; then
        echo "Switching $project_name from branch $current_branch to $branch..."
        eval "$git_ssh_command git fetch origin"
        # Try checking out, if fails, try fetching specific branch and then checkout
        if ! eval "$git_ssh_command git checkout $branch"; then
            echo "Checkout failed, attempting to fetch specific branch $branch..."
            if eval "$git_ssh_command git fetch origin $branch:$branch" && eval "$git_ssh_command git checkout $branch"; then
                echo "Successfully switched to branch $branch after fetching."
            else
                echo "❌ Failed to switch $project_name to branch $branch even after specific fetch. Please check the remote repository and branch name."
                return 1
            fi
        fi
      fi
      
      echo "Pulling latest changes for $project_name on branch $branch..."
      if eval "$git_ssh_command git pull origin $branch"; then
        echo "✅ $project_name updated successfully."
      else
        echo "⚠️ Failed to pull $project_name. Check for conflicts or issues on the server. Local changes might prevent pulling."
        # return 1 # Decide if a pull failure should stop the whole script
      fi
    elif [ -d "$remote_dir" ] && [ -n "$(ls -A "$remote_dir" 2>/dev/null)" ]; then
      echo "⚠️ Directory $remote_dir exists but is not a clean git repository or is not empty. Please manually inspect."
      echo "Skipping $project_name deployment to avoid data loss."
      return 1
    else
      echo "Cloning $project_name repository to $remote_dir on branch $branch..."
      # Ensure directory exists just before cloning into it, if it was removed or never created.
      if ! mkdir -p "$remote_dir"; then
          echo "❌ Failed to create directory $remote_dir for cloning $project_name."
          return 1
      fi
      if eval "$git_ssh_command git clone --branch $branch $git_url $remote_dir"; then
        echo "✅ $project_name cloned successfully."
      else
        echo "❌ Failed to clone $project_name. Check URL, branch, permissions, and if the target directory is empty."
        return 1
      fi
    fi
    echo "-----------------------------------------------------"
  }

  manage_repo "$MF_GIT_URL" "$MF_GIT_BRANCH" "$MF_REMOTE_DIR" "$MF_PROJECT_NAME"
  manage_repo "$MC_GIT_URL" "$MC_GIT_BRANCH" "$MC_REMOTE_DIR" "$MC_PROJECT_NAME"

  echo "✅ All Git operations complete."
EOF_REMOTE_SCRIPT

if [ $? -eq 0 ]; then
  echo "✅ Deployment script executed successfully on server."
else
  echo "❌ Deployment script on server encountered errors."
fi

echo "🚀 Full deployment process finished."
