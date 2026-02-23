# Self-Aware Autonomy Architecture
## The Agent Knows What It Has (And What It's Missing)

### Core Concept

When autonomy spins up, it doesn't just check if files exist. It:
1. **Audits available integrations** - Git, GitHub, Discord, SSH, APIs
2. **Maps capability gaps** - "I can git commit but can't push to GitHub"
3. **Offers guided onboarding** - "Want me to set up GitHub? Run: `clawhub setup github`"
4. **Degrades gracefully** - Works with what it has, guides to get more

### The Onboarding Flow

```
User: "Deploy this to production"

Autonomy thinks:
├─ Do I have SSH access to production? [NO]
├─ Do I have Docker? [YES]
├─ Do I have registry push access? [NO]
└─ Can I reach the server? [UNKNOWN]

Response:
"I can build the Docker image, but I need a few things to deploy:

  ❌ SSH access to production server
     → Set up: `autonomy setup ssh prod-server`

  ❌ Registry credentials  
     → Set up: `autonomy setup registry dockerhub`

  ✅ Docker build capability

Want me to help configure the missing pieces, or just build the 
image and give you the deploy commands?"
```

### Capability Registry

File: `autonomy/capabilities.json`

```json
{
  "integrations": {
    "git": {
      "available": true,
      "provider": "system",
      "version": "2.43.0",
      "capabilities": ["commit", "push", "branch", "stash"],
      "limitations": ["no_github_cli"]
    },
    "github": {
      "available": false,
      "reason": "gh cli not installed",
      "setup_command": "clawhub install gh-cli",
      "workaround": "use git https with token"
    },
    "discord": {
      "available": true,
      "provider": "openclaw-channel",
      "account": "autonomy-bot",
      "capabilities": ["notify", "dm", "slash_commands"]
    },
    "ssh": {
      "available": true,
      "hosts": ["localhost"],
      "key_based_auth": false,
      "password_auth": false
    }
  },
  "tools": {
    "docker": { "available": true, "version": "24.0.7" },
    "kubectl": { "available": false, "setup": "clawhub install kubectl" },
    "aws": { "available": false, "reason": "no credentials configured" }
  }
}
```

### The Capability Auditor

```bash
#!/bin/bash
# audits.sh - Self-awareness system

audit_all() {
    echo "{"
    echo '  "audited_at": "'$(date -Iseconds)'",'
    echo '  "integrations": {'
    
    # Git
    if command -v git &> /dev/null; then
        echo '    "git": {'
        echo '      "available": true,'
        echo '      "version": "'$(git --version | cut -d" " -f3)'",'
        echo '      "capabilities": ["commit", "push", "branch", "stash", "merge"]'
        echo '    },'
    else
        echo '    "git": { "available": false, "install": "apt install git" },'
    fi
    
    # GitHub CLI
    if command -v gh &> /dev/null; then
        echo '    "github_cli": { "available": true },'
    else
        echo '    "github_cli": { '
        echo '      "available": false,'
        echo '      "setup_command": "clawhub install gh-cli",'
        echo '      "workaround": "use git with https token"'
        echo '    },'
    fi
    
    # Discord (via OpenClaw)
    if openclaw channels list | grep -q "discord"; then
        echo '    "discord": { "available": true, "provider": "openclaw" }'
    else
        echo '    "discord": { '
        echo '      "available": false,'
        echo '      "setup_command": "openclaw channels add --channel discord --token TOKEN"'
        echo '    }'
    fi
    
    echo '  }'
    echo "}"
}

# Check specific capability
can_do() {
    local action="$1"
    
    case "$action" in
        github_pr_create)
            if command -v gh &> /dev/null; then
                echo "yes"
            else
                echo "no:gh_cli_not_installed"
            fi
            ;;
        docker_build)
            if command -v docker &> /dev/null; then
                echo "yes"
            else
                echo "no:docker_not_installed"
            fi
            ;;
        ssh_deploy)
            if [[ -f ~/.ssh/id_rsa ]] || [[ -f ~/.ssh/id_ed25519 ]]; then
                echo "yes"
            else
                echo "no:ssh_key_missing"
            fi
            ;;
    esac
}

# Suggest setup for missing capability
how_to_enable() {
    local capability="$1"
    
    case "$capability" in
        github)
            echo "Setup GitHub CLI:"
            echo "  1. clawhub install gh-cli"
            echo "  2. gh auth login"
            echo "  Or use git with token: git remote set-url origin https://TOKEN@github.com/..."
            ;;
        ssh)
            echo "Setup SSH:"
            echo "  1. ssh-keygen -t ed25519"
            echo "  2. Add pubkey to server: ~/.ssh/id_ed25519.pub"
            ;;
        aws)
            echo "Setup AWS:"
            echo "  1. clawhub install aws-cli"
            echo "  2. aws configure"
            ;;
    esac
}
```

### The Smart Executor

```python
class SmartExecutor:
    def __init__(self):
        self.capabilities = self.load_capabilities()
    
    def execute(self, task):
        """
        Execute task OR explain what's missing
        """
        required = self.analyze_requirements(task)
        missing = self.find_gaps(required)
        
        if missing:
            return {
                "status": "blocked",
                "reason": "missing_capabilities",
                "missing": missing,
                "setup_commands": [self.get_setup_command(m) for m in missing],
                "workarounds": [self.get_workaround(m) for m in missing],
                "can_partially_do": self.can_degrade(task, missing)
            }
        
        return self.actually_execute(task)
    
    def analyze_requirements(self, task):
        """
        Parse task for required capabilities
        """
        requirements = []
        
        if "deploy" in task.lower():
            requirements.extend(["ssh", "docker", "kubectl"])
        
        if "github" in task.lower() or "pr" in task.lower():
            requirements.append("github_cli")
        
        if "aws" in task.lower() or "s3" in task.lower():
            requirements.append("aws_cli")
        
        return requirements
    
    def find_gaps(self, requirements):
        """Find which requirements aren't met"""
        return [r for r in requirements if not self.capabilities.get(r, {}).get("available")]
```

### Example Interaction

```
User: "Deploy the webapp to production"

Autonomy:
┌─────────────────────────────────────────┐
│  🚀 Deploy Analysis                     │
├─────────────────────────────────────────┤
│                                         │
│  I can help with this deployment, but   │
│  I need a few things configured:        │
│                                         │
│  ❌ SSH access to production            │
│     → Run: autonomy setup ssh prod      │
│                                         │
│  ❌ kubectl context for prod            │
│     → Run: autonomy setup k8s prod      │
│                                         │
│  ✅ Docker build (available)            │
│  ✅ Git access (available)              │
│                                         │
│  What I CAN do right now:               │
│  • Build the Docker image               │
│  • Run tests                            │
│  • Show you the deployment commands     │
│                                         │
│  [Build Image] [Setup SSH] [Skip]       │
└─────────────────────────────────────────┘
```

### The Setup Wizard

```bash
autonomy setup ssh prod-server
# → Checks if SSH key exists
# → If not: generates key, shows pubkey to copy
# → Tests connection
# → Saves to capabilities.json

autonomy setup github
# → Checks for gh CLI
# → If not: offers to install via clawhub
# → Guides auth flow
# → Verifies access

autonomy setup k8s prod
# → Checks kubectl
# → Lists available contexts
# → Tests connection
# → Saves as 'prod' alias
```

### Benefits

1. **No silent failures** - Always knows what it can't do
2. **Guided onboarding** - User doesn't need to research setup
3. **Graceful degradation** - Works with partial capabilities
4. **Self-documenting** - Capabilities.json shows what's available
5. **Composable** - Can chain setups (setup ssh → setup k8s → deploy)

### Implementation Priority

1. **Now:** Add `audit.sh` that generates capabilities.json
2. **Next:** Modify executor to check capabilities before acting
3. **Then:** Add setup commands for common integrations
4. **Finally:** UI for "I want to do X" → guided setup flow

This makes autonomy **truly self-aware** - not just monitoring files, but monitoring its own ability to help.
