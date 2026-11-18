MACHINE_HOST=ambrosia
BACKUP_HOST=ambrosia.local
BASE=/Users/avirut/Documents/Projects/kroacnet/private/backups/restic/stage
SQLITE=/opt/homebrew/opt/sqlite/bin/sqlite3
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
EXCLUDES=('*-wal' '*-shm' '*.lock' '*.claim' '*.tmp' '*.sock' '.DS_Store')
prepare_apps() {
    copy_optional /Users/avirut/.paseo/config.json
    copy_optional /Users/avirut/.paseo/daemon-keypair.json
    copy_optional /Users/avirut/.paseo/server-id
    copy_optional /Users/avirut/.paseo/local-credential
    copy_optional /Users/avirut/.paseo/cli-client-id
    copy_optional /Users/avirut/.paseo/hub-relationship.json
    copy_optional /Users/avirut/.paseo/hub-credentials.json
    copy_optional /Users/avirut/.paseo/agents
    copy_optional /Users/avirut/.paseo/projects/projects.json
    copy_optional /Users/avirut/.paseo/projects/workspaces.json
    copy_optional /Users/avirut/.codex/config.toml
    copy_optional /Users/avirut/.codex/auth.json
    copy_optional /Users/avirut/.codex/session_index.jsonl
    copy_optional /Users/avirut/.codex/sessions
    copy_optional /Users/avirut/.codex/state_5.sqlite
    copy_optional /Users/avirut/.codex/thread_history_1.sqlite
    copy_optional /Users/avirut/.codex/goals_1.sqlite
    copy_optional /Users/avirut/.codex/queue_1.sqlite
    copy_optional /Users/avirut/.codex/memories_1.sqlite
    copy_optional /Users/avirut/.claude.json
    copy_optional /Users/avirut/.claude/projects
    copy_optional /Users/avirut/.claude/settings.json
    copy_optional /Users/avirut/.claude/CLAUDE.md
    copy_optional /Users/avirut/.claude/history.jsonl
    copy_optional /Users/avirut/.claude/plans
    copy_optional /Users/avirut/.claude/tasks
    copy_optional /Users/avirut/Library/LaunchAgents/net.kroac.paseo.plist
    copy_optional /Users/avirut/.local/bin/paseo
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
