# my-claude-skills

Claude Code skills — portable workflow primitives and composite skills for software development.

## Installation

```bash
git clone git@github.com:couimet/my-claude-skills.git ~/src/my-claude-skills
~/src/my-claude-skills/install.sh
```

This creates symlinks from `~/.claude/skills/` to the repo, making all skills globally available in every Claude Code project.

### Updating

```bash
cd ~/src/my-claude-skills && git pull && ./install.sh
```

The install script is idempotent — safe to run on every pull. It only creates/updates symlinks; it never deletes non-symlink directories.

## Skills

See [skills/README.md](skills/README.md) for the full inventory and architecture.
