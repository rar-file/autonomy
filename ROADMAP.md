# Autonomy Enhancement Roadmap
## Making It Actually Useful

### Current Problem
- Heartbeat checks are generic
- No real integration with actual workflows
- Just "monitoring" for the sake of monitoring

### Solution: Context-Specific Intelligence

## 1. Git-Aware Development Context

**What it does:**
- Detects you're coding (file changes in git repos)
- Auto-suggests commits when changes sit >2 hours
- Warns about uncommitted work before context switches
- Tracks which branches have unpushed commits
- Monitors PR status (if GitHub CLI available)

**Checks:**
- `git_dirty_check` - Warns if working directory dirty >2h
- `git_stale_branch` - Flags branches with unpushed commits >24h
- `git_commit_suggest` - Suggests commit messages based on diff

**Value:** Never lose work, never forget to push, always know PR status

## 2. Security Automation Context

**What it does:**
- Scans code for security issues on save
- Checks dependencies for CVEs
- Monitors secrets (prevents accidental commits)
- Tracks security-related TODOs in code
- Alerts on configuration drift

**Checks:**
- `security_lint` - Runs bandit, semgrep on Python files
- `cve_check` - Scans requirements.txt for known vulnerabilities
- `secrets_scan` - Checks for API keys, tokens in staged files
- `config_audit` - Validates security settings in configs

**Value:** Security by default, catch issues before commit

## 3. Project Intelligence Context

**What it does:**
- Tracks which files you actually work on
- Builds a "hot files" map of your codebase
- Suggests related files when you open one
- Detects when you're stuck (same file open for hours)
- Suggests breaks after long sessions

**Checks:**
- `activity_pattern` - Tracks file access patterns
- `stuck_detection` - Alerts if same file open >3h
- `context_suggest` - "You usually edit X when editing Y"
- `break_reminder` - "You've been at this for 4 hours"

**Value:** Understands your workflow, helps you work smarter

## 4. Documentation Maintenance Context

**What it does:**
- Watches for code changes that should update docs
- Detects README.md drift from actual code
- Suggests doc updates based on function signature changes
- Tracks TODO comments in code
- Reminds about stale documentation

**Checks:**
- `doc_drift` - Compares README to actual code structure
- `todo_tracker` - Lists all TODO/FIXME comments
- `api_doc_sync` - Checks if function docs match signatures
- `changelog_reminder` - "You made breaking changes, update CHANGELOG"

**Value:** Docs stay current without manual effort

## 5. System Health Context

**What it does:**
- Monitors disk space, memory, load
- Tracks Docker container health
- Watches for zombie processes
- Alerts on service failures
- Checks SSL certificate expiry

**Checks:**
- `resource_usage` - Disk, memory, CPU trends
- `docker_health` - Container status
- `service_status` - Custom service health checks
- `ssl_expiry` - Certificate expiration warnings

**Value:** Proactive system maintenance

## Implementation Strategy

### Phase 1: Smart Defaults (Now)
- Auto-detect project type (Python, Node, etc.)
- Suggest relevant contexts
- Intelligent defaults for check frequency

### Phase 2: Learning Mode (Next)
- Track what checks actually catch issues
- Auto-disable noisy checks
- Learn your schedule (don't alert at 3am)

### Phase 3: Predictive (Future)
- "You're about to deploy, run tests first?"
- "That file usually causes bugs, extra careful?"
- "You haven't committed in 2 hours, everything ok?"

## Smart Check Logic

```python
# Instead of:
"Check git status every 20 minutes"

# Do:
"Check git status when:
 - Files have been modified for >2 hours
 - User is about to switch contexts
 - It's end of workday
 - Large batch of changes detected"
```

## User Control

```bash
# Smart defaults
autonomy on --smart

# Override specific behavior  
autonomy config set git.commit_reminder_delay 30m
autonomy config set security.cve_check_frequency daily
autonomy config disable check.break_reminder

# Learning mode
autonomy learn on  # Adapts to your patterns

# Review what autonomy has learned
autonomy insights  # Shows patterns detected
```

## Success Metrics

Not "checks ran" but:
- Issues caught before they became problems
- Time saved from automated reminders
- Context switches that were actually needed
- Docs that stayed current
- Security issues caught early

## Next Steps

1. Pick ONE context to implement first (Git-Aware?)
2. Make it genuinely useful for your workflow
3. Dogfood it - use it for a week
4. Iterate based on what actually helps

Which context resonates most with your actual work?
