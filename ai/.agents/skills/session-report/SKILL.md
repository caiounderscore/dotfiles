---
name: session-report
description: Produce a short, evidence-grounded end-of-session report about how the user could provide better context and prompts, with optional authoritative usage metadata when the current client exposes it. Use when the user asks for a session report or retrospective.
---

# Session Report

Review only the current conversation. Use concise bullets and omit generic advice.

## How to improve the next session

Return three to five concrete observations tied to moments in this session. Consider:

- context starvation or irrelevant context flooding;
- missing examples or repository conventions;
- ambiguity that caused guessing or extra back-and-forth;
- stale assumptions during a long-running task;
- constraints, acceptance criteria, or output format that arrived too late.

For each real issue, name the specific missing input or prompt change that would have prevented it. Do not request hidden reasoning or recommend exposing chain-of-thought.

## Optional usage

- Include usage only when the current client already exposes authoritative session metadata to the agent through a safe local capability.
- Do not invoke an assumed slash command, start another agent session, make a network request, or estimate billing.
- Distinguish subscription allowance from API/pay-as-you-go billing only when the plan is known from authoritative metadata; never infer it.
- If usage is unavailable and the user explicitly requested it, say that it is unavailable. Otherwise omit this section.
