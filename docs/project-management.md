# Project Management

## Why Trello

Trello was chosen because it provides a low-friction operational board that works well for human operators and AI agents. The card and list model is simple enough to stay readable during infrastructure work, and explicit enough to preserve execution state across sessions.

## How AI Agents Interact With Trello

AI agents create and maintain cards for major workstreams, move cards to `Doing` when active, move them to `Done` when complete, and move them to `Blocked` when progress depends on missing credentials, external systems, or user intervention. Comments on blocked cards explain both the reason and the required action.

## Task Flow

- `To Do`: not started yet
- `Doing`: actively being implemented or verified
- `Blocked`: cannot continue because a dependency is missing
- `Done`: completed and validated within the current context

## Blocked Task Handling

Blocked work is never left implicit. The blocking condition must be written to the card, including what the operator needs to provide, such as provider credentials, DNS, or repository settings not exposed through automation.

## Why The Board Matters

Infrastructure projects become chaotic when planning lives only in terminal history. The board keeps intent, state, and ownership visible, prevents half-finished automation from disappearing, and gives both AI and human operators a shared source of operational truth.
