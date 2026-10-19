# Native Mac source owner and reviewed coverage.
MACHINE_HOST=ambrosia
BACKUP_HOST=ambrosia.local
BASE=/Users/avirut/Documents/Projects/kroacnet/private/backups/restic/stage
SQLITE=/opt/homebrew/opt/sqlite/bin/sqlite3
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
EXCLUDES=('*-wal' '*-shm' '*.lock' '*.claim' '*.tmp' '*.sock' '.DS_Store')
copy_optional() { if [[ -e $1 ]]; then copy_source "$@"; fi; }
prepare_apps() {
    copy_source /Users/avirut/.paseo/config.json
    copy_source /Users/avirut/.paseo/daemon-keypair.json
    copy_source /Users/avirut/.paseo/server-id
    copy_source /Users/avirut/.paseo/local-credential
    copy_source /Users/avirut/.paseo/cli-client-id
    copy_source /Users/avirut/.paseo/hub-relationship.json
    copy_source /Users/avirut/.paseo/hub-credentials.json
    copy_source /Users/avirut/.paseo/agents
    copy_source /Users/avirut/.paseo/projects/projects.json
    copy_source /Users/avirut/.paseo/projects/workspaces.json
    copy_source /Users/avirut/.codex/config.toml
    copy_source /Users/avirut/.codex/auth.json
    copy_source /Users/avirut/.codex/session_index.jsonl
    copy_source /Users/avirut/.codex/sessions
    copy_source /Users/avirut/.codex/state_5.sqlite
    copy_source /Users/avirut/.codex/thread_history_1.sqlite
    copy_source /Users/avirut/.codex/goals_1.sqlite
    copy_source /Users/avirut/.codex/queue_1.sqlite
    copy_source /Users/avirut/.codex/memories_1.sqlite
    copy_source /Users/avirut/.claude.json
    copy_source /Users/avirut/.claude/projects
    copy_source /Users/avirut/.claude/settings.json
    copy_source /Users/avirut/.claude/CLAUDE.md
    copy_source /Users/avirut/.claude/history.jsonl
    copy_source /Users/avirut/.claude/plans
    copy_source /Users/avirut/.claude/tasks
    copy_source /Users/avirut/Library/LaunchAgents/net.kroac.paseo.plist
    copy_source /Users/avirut/.local/bin/paseo
    copy_optional /Users/avirut/.paseo/push-tokens.json
    copy_optional /Users/avirut/.paseo/agent-requests
    copy_optional /Users/avirut/.paseo/creations
    copy_optional /Users/avirut/.paseo/schedules
    copy_optional /Users/avirut/.codex/installation_id
    copy_optional /Users/avirut/.codex/archived_sessions
    copy_optional /Users/avirut/.codex/history.jsonl
    copy_optional /Users/avirut/.codex/memories
    copy_optional /Users/avirut/.codex/AGENTS.md
    copy_optional /Users/avirut/.codex/rules
    copy_optional /Users/avirut/.codex/skills '/.system/'
    copy_optional /Users/avirut/.claude/plugins/known_marketplaces.json
}
