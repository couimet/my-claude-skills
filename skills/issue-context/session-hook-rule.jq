# session-hook-rule.jq — the jq definitions that find the entries of the
# session hook (session-hook.sh) in a Claude Code settings file. install.sh
# and session-hook-state.sh read this one file, so the two never disagree on
# what counts as the hook.
#
# An entry is the hook's when its command ends with the path below the skills
# directory, so a link to another checkout, a hand-written ~ path, and the
# ${CLAUDE_PLUGIN_ROOT} path of hooks/hooks.json all count.
def ours: ((.command // "") | tostring | endswith("/issue-context/session-hook.sh"));
def strip: map(.hooks = ((.hooks // []) | map(select(ours | not))))
           | map(select((.hooks | length) > 0));
