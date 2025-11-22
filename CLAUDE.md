## Claude-Handoff Plugin

**Goal**: Replace Claude Code's lossy `/compact` feature with `/handoff` - an intelligent context transfer system that creates focused, goal-oriented thread transitions.

### What It Does

When you invoke `/handoff <your new goal>`, the plugin:
1. Analyzes the current thread for relevant context
2. Generates a draft prompt optimized for starting a new thread
3. Identifies and attaches a curated list of relevant files

### Why It Matters

Compaction is lossy - each summary degrades context quality and encourages unfocused threads. Handoff preserves intentionality by extracting only what matters for your specific next step, producing better results from AI agents through focused thread design.

### Usage Examples

```bash
/handoff now implement this for teams as well, not just individual users
/handoff execute phase one of the created plan
/handoff check the rest of the codebase and find other places that need this fix
```

The generated content appears as an editable draft, letting you refine before starting the new thread.
