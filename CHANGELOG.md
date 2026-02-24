# Changelog

## [1.2.0] - 2026-02-24 - Continuous Improvement

### Added
- Activity Viewer (autonomy activity) - View history with filters
- Health Check (autonomy health) - Comprehensive diagnostics  
- Bash Completions - Tab completion for all commands
- Smart Error Messages - Actionable suggestions when things fail
- Unified Logging (lib/logging.sh) - Consistent JSON logging

### Improved
- README - Added new commands, better formatting
- Code Quality - Removed test artifacts, added .gitignore
- Error Handling - Better messages with fix suggestions

### Technical
- Added lib/ directory for shared utilities
- Added completions/ for shell integrations
- Cleaner repository structure

### TODO for Next Session
- [ ] Fix Discord status persistence issue
- [ ] Add more unit tests (target: 50 tests)
- [ ] Create setup wizard for first-time users
- [ ] Add context inheritance feature
- [ ] Improve check dependency system
