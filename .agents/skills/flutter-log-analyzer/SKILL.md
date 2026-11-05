---
name: flutter-log-analyzer
description: Analyze dev_data/flutter.log for errors, performance problems and process issues. Use when asked to check the app logs, review performance after a change, or find runtime errors.
---

# Flutter log analysis

Read `agent.md` in this skill directory and follow it exactly. It is the agent definition
and the single source of truth for the performance thresholds and the output format.

For a log larger than about 2,000 lines, give the agent file and the log path to a
subagent. Do not copy the thresholds into this skill.
