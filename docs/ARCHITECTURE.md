# AI OS architecture

## Scope

Milestone 0B creates stable boundaries for later capabilities without adding
those capabilities. All behavior is local and offline. The Flutter Windows
runner remains the platform host, while domain abstractions are plain Dart.

## Layers and responsibilities

- `app/` is the composition root and temporary Flutter application shell. It is
  the only place where concrete services are selected and wired together.
- `core/` contains cross-cutting primitives: configuration, events, results,
  authorization, and orchestration.
- `ai/model_provider/` defines provider-neutral conversations, responses, and
  future tool-call requests. Its mock provider supports deterministic tests.
- `agents/` defines specialized coordinators. The PC Agent advertises tools but
  intentionally performs no computer control in this milestone.
- `tools/` defines structured metadata, input schemas, execution results, and
  the authorization gate. Category placeholders perform no real actions.
- `memory/` defines storage operations and supplies a process-local map.
- `skills/` represents reusable workflows with metadata and one entry point.
- `mcp/` is a discovery boundary through which future MCP servers may expose
  ordinary `Tool` objects. Its current implementation is offline and empty.

## Dependency direction

Concrete platform/provider implementations depend inward on abstractions.
The orchestrator knows `ModelProvider`, `Agent`, `Tool`, and `EventPublisher`,
but not Ollama, OpenAI, Windows APIs, an MCP transport, or Flutter widgets.
The composition root owns all concrete choices. UI code depends on the
orchestrator and never on a provider implementation.

```text
Flutter shell -> Orchestrator -> ModelProvider interface
                           |-> Agent interface -> Tool interface
                           |-> EventPublisher
Tool implementation -> authorization boundary -> operation
MCP implementation -> Tool interface
Composition root -> all concrete implementations
```

## Orchestrator flow

1. Validate the user request and return `Result.failure` for expected errors.
2. Publish a request event.
3. Convert available tools into provider-neutral tool definitions.
4. Send provider-neutral messages to the configured `ModelProvider`.
5. Return the assistant message and any requested tool calls in a structured
   `Result`, then publish a completion event.

Tool calls are data only in Milestone 0B. They are not executed. Future routing
can select an agent and invoke a tool through the same authorization boundary
without changing model-provider contracts.

## Agent and tool relationship

An agent exposes the tools available to its responsibility and handles an
`AgentRequest`. A tool has a stable ID, descriptive metadata, an AI-callable
input schema, required permissions, and structured output. `AuthorizedTool`
checks every requested permission before calling a concrete operation. The PC
Agent and all category tools explicitly report `not_implemented` today.

## Model providers and future local AI

`ModelProvider` exchanges role-based messages and `ModelResponse` objects that
can carry future tool calls. Adding Ollama or another local engine means adding
a provider adapter and selecting it in the composition root. The orchestrator,
agents, tools, memory, and UI do not need to import that adapter.

The core must remain provider-agnostic because model availability, protocols,
and tool-call formats vary. Keeping translation in adapters prevents provider
changes from forcing application-wide rewrites and keeps tests offline.

## Future MCP integration

An MCP adapter will implement `McpGateway`, translate discovered MCP tools into
the existing `Tool` contract, and translate execution inputs/results at the
edge. To the orchestrator, built-in and MCP-discovered tools remain the same
kind of object. No MCP networking or external server is present yet.

## Security boundary

Permissions are `read`, `write`, `execute`, and `sensitive`. A tool declares
what it needs; `AuthorizedTool` submits a `PermissionRequest` before concrete
execution. The current allow-list policy is deliberately small and local.
Future consent prompts, audit logs, resource scopes, and persistent policies
can implement `PermissionAuthorizer` without allowing tools to bypass it.

## Configuration and memory

`AppConfiguration` holds the provider selection, optional local-model settings,
permissions, feature flags, and storage locations. It is local and injected at
startup. `MemoryStore` supplies store/retrieve/delete operations; the current
implementation is volatile and intentionally has no vector or cloud backend.
