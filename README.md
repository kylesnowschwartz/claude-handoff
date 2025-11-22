# Claude-Handoff

Intelligent context transfer for Claude Code - replace lossy compaction with focused thread transitions.

## What It Does

Claude-Handoff replaces the `/compact` feature with `/handoff` - an intelligent system that analyzes your current thread and generates a focused prompt for starting a new thread based on your specific goal.

## Why?

Compaction is lossy. Every summary degrades context quality and encourages unfocused threads. Handoff preserves intentionality by:
- Analyzing the current thread for relevant context
- Generating a draft prompt optimized for your goal
- Identifying and attaching relevant files
- Presenting editable output before you commit

## Installation

```bash
# From your project directory
claude plugin add /path/to/claude-handoff
```

## Usage

```bash
# Hand off to implement a feature for teams
/handoff now implement this for teams as well, not just individual users

# Hand off to execute a specific phase
/handoff execute phase one of the created plan

# Hand off to find similar issues
/handoff check the rest of the codebase and find other places that need this fix
```

The plugin generates a draft prompt and file list that you can review and edit before starting your new thread.

## Development

This plugin follows the Claude Code plugin architecture:
- `.claude-plugin/marketplace.json` - Local marketplace definition
- `handoff-plugin/.claude-plugin/plugin.json` - Plugin metadata
- `handoff-plugin/commands/` - Slash commands
- `handoff-plugin/hooks/` - Hook implementations

## License

MIT - See LICENSE file for details
