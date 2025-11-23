## Claude-Handoff Plugin

**Goal**: Transform `/compact` into a goal-focused context handoff system that preserves intentionality across thread transitions.

### What It Does

When you invoke `/compact handoff:<your new goal>`, the plugin:
1. Captures your goal and current session state before compaction
2. Analyzes the previous thread to extract ONLY context relevant to your goal
3. Injects focused context as a system message in the new session
4. Automatically starts the new session after compact completes

### Why It Matters

Traditional compaction is lossy and unfocused - each summary degrades context quality. Goal-focused handoff extracts only what matters for your specific next step, producing sharper results through ruthless selectivity.

### Usage

**Trigger handoff:**
```bash
/compact handoff:now implement this for teams as well, not just individual users
/compact handoff:execute phase one of the created plan
/compact handoff:find other places in the codebase that need this same fix
```

**Regular compact** (no handoff):
```bash
/compact
/compact keep the context tight
```

### How It Works

1. **PreCompact Hook**: Activates only when you use `/compact handoff:...` format
   - Extracts your goal from the `handoff:` prefix
   - Saves session ID and goal to `.git/handoff-pending/handoff-context.json`

2. **Compact**: Proceeds normally, creating a new session

3. **SessionStart Hook**: Runs in the new session
   - Reads your goal from the saved state
   - Uses `claude --resume <previous-session>` with your goal as context filter
   - Generates goal-focused handoff containing only relevant context
   - Injects handoff as system message

4. **Result**: New session starts with focused context, ready to execute your goal

### Configuration

Enable debug logging: Edit `handoff-plugin/hooks/lib/logging.sh` and set `LOGGING_ENABLED=true`

View logs:
```bash
tail -f /tmp/handoff-precompact.log
tail -f /tmp/handoff-sessionstart.log
```
