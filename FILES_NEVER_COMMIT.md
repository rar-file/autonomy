# FILES_NEVER_COMMIT.md
# These files/directories should NEVER be committed to GitHub
# They are local development artifacts, runtime data, or contain sensitive info

## NEVER Commit These:

### Runtime / Generated Data
- .autonomy/              # Autonomy system runtime data
- .autonomy_triggers/     # Trigger files for autonomy
- .autonomy_logs/         # Log files
- logs/                   # All log directories
- tasks/                  # Runtime task storage
- test_output/            # Test artifacts

### Development Scripts (Temporary)
- fix_personality.py      # One-time fix scripts
- test_autonomy.py        # Local test files
- *.tmp                   # Temporary files
- *.log                   # Log files

### Web UI / Dashboard (Separate Project)
- web_ui.py               # Web dashboard (separate repo)
- templates/              # HTML templates for web UI
- static/                 # Static assets for web UI

### Research / Notes
- RESEARCH_*.md           # Research documents (keep local)
- notes/                  # Personal notes directory

### Python Artifacts
- __pycache__/            # Python cache
- *.pyc                   # Compiled Python
- .pytest_cache/          # Test cache
- venv/                   # Virtual environment

### System Files
- .DS_Store               # macOS files
- Thumbs.db               # Windows files
- *.swp                   # Vim swap files
- *~                      # Backup files

## What SHOULD Be Committed:
- SKILL.md, README.md, USAGE.md (core documentation)
- autonomy (CLI script)
- install.sh, config.json (installation/config)
- tests/run_tests.sh (tests)
- assets/ (logos, diagrams)
- .github/workflows/ (CI/CD)
- .gitignore (this exclusion list)

## How to Check Before Commit:
# Run this before every commit:
git status
# Review the list - if you see files from NEVER_COMMIT list:
git rm --cached <file>
# Or reset if already staged:
git reset HEAD <file>

## Prevention:
# This file is automatically checked by pre-commit (if configured)
# And referenced in .gitignore
