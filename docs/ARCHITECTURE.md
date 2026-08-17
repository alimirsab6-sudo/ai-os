# AI OS architecture

## Scope

Milestone 3C.1 retains the earlier boundaries and adds local Chrome profile
discovery, validated profile-aware launch, a Browser Agent routing boundary,
and selected-profile BrowserSession state. Value/SetValue, Invoke, generic
Chrome launch, window discovery/control, and UI
inspection remain intact. The Flutter Windows runner remains unchanged, and
platform-neutral models/interfaces remain plain Dart.

## Layers and responsibilities

- `app/` is the composition root and temporary Flutter application shell. It is
  the only place where concrete services are selected and wired together.
- `core/` contains cross-cutting primitives: configuration, events, results,
  authorization, and orchestration.
- `ai/model_provider/` defines provider-neutral conversations, responses, and
  future tool-call requests. Its mock provider supports deterministic tests.
- `agents/` defines specialized coordinators. The PC Agent routes structured
  launch, discovery, top-level window control, bounded UI inspection, and
  semantic Invoke and SetValue requests to configured tools.
- `agents/browser_agent/` routes Chrome profile discovery/launch and validated
  HTTP(S) URL opening. It owns no tabs or website interaction behavior.
- `browser/` holds application-neutral browser session state plus isolated
  Chrome profile and Windows launch adapters.
- `tools/` defines structured metadata, input schemas, execution results, and
  the authorization gate. Windows application resolution and launching are
  isolated below `tools/windows/`; native Win32 details stay in the discovery
  adapter, and other category placeholders do nothing.
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

## Orchestrator flows

The approved CronyX shell uses a deterministic command interpreter for the
small Phase 1 command vocabulary. A recognized request becomes an existing
structured `OrchestratorCommand`; unrecognized text returns
`unsupported_command` and is never treated as a process or shell string.

```text
Command bar / Quick Action
  -> Orchestrator.handle(text)
  -> DeterministicCommandInterpreter
  -> LaunchApplicationCommand / OpenUrlCommand
  -> PC Agent / Browser Agent
  -> permission-checked Tool
  -> structured Result + EventBus lifecycle
  -> Core, HUD, Live Action, Activity
```

`OpenUrlCommand` accepts only absolute HTTP(S) URLs without user-info. Its
Windows adapter resolves Edge or Chrome through the application allow-list and
starts that executable directly with one URL argument and `runInShell: false`.

The provider-oriented flow established in Milestone 0B remains available:

1. Validate the user request and return `Result.failure` for expected errors.
2. Publish a request event.
3. Convert available tools into provider-neutral tool definitions.
4. Send provider-neutral messages to the configured `ModelProvider`.
5. Return the assistant message and any requested tool calls in a structured
   `Result`, then publish a completion event.

Provider-generated tool calls remain data only and are not executed. Milestone
1 adds a separate deterministic structured route:

```text
LaunchApplicationCommand("chrome")
  -> Orchestrator
  -> PC Agent
  -> LaunchApplicationTool
  -> PermissionAuthorizer(execute)
  -> ApplicationRegistry
  -> WindowsProcessLauncher
  -> Chrome
```

This route never calls `ModelProvider`. It emits `pc.command.requested`,
`tool.started`, `tool.succeeded` or `tool.failed`, and, after success,
`application.launched`.

Milestone 2A adds two more deterministic routes:

```text
ListWindowsCommand / GetActiveWindowCommand
  -> Orchestrator
  -> PC Agent
  -> ListWindowsTool / GetActiveWindowTool
  -> PermissionAuthorizer(read)
  -> WindowDiscovery
  -> WindowsWindowDiscovery
```

These routes emit `window.discovery.requested`, followed by
`window.discovery.started` and either `window.discovery.succeeded` or
`window.discovery.failed`. They never consult `ModelProvider`.

Milestone 2B adds structured `ActivateWindowCommand`,
`MinimizeWindowCommand`, `MaximizeWindowCommand`, `RestoreWindowCommand`, and
`CloseWindowCommand` routes:

```text
WindowControlCommand(runtimeWindowId)
  -> Orchestrator
  -> PC Agent
  -> operation-specific Tool
  -> PermissionAuthorizer
  -> WindowController
  -> current WindowDiscovery validation
  -> WindowsWindowController
```

The route emits `window.control.requested`, `window.control.started`, and either
`window.control.succeeded` or `window.control.failed`. Each event identifies the
operation and runtime window ID; completion events also state success/failure.

Milestone 3A adds a deterministic inspection route:

```text
InspectUiCommand(windowId, maxDepth, maxElements)
  -> Orchestrator
  -> PC Agent
  -> InspectUiTool
  -> PermissionAuthorizer(read)
  -> current WindowDiscovery validation
  -> UiAutomation
  -> Windows UI Automation COM adapter (background isolate)
```

The route emits `ui.inspection.requested`, `ui.inspection.started`, and either
`ui.inspection.succeeded` or `ui.inspection.failed`. Events identify the window
and limits; successful completion also reports element count and truncation.

Milestone 3B.1 adds:

```text
InvokeUiElementCommand(windowId, elementId)
  -> Orchestrator
  -> PC Agent
  -> InvokeUiElementTool
  -> PermissionAuthorizer(execute)
  -> current WindowDiscovery validation
  -> UiAutomation.invoke
  -> fresh COM re-resolution and identity validation
  -> IUIAutomationInvokePattern.Invoke
```

No model provider participates. Events are `ui.invoke.requested`,
`ui.invoke.started`, and either `ui.invoke.succeeded` or `ui.invoke.failed`;
each contains the target window ID and opaque element ID, and completion events
include success/failure metadata.

Milestone 3B.2 adds:

```text
SetUiElementValueCommand(windowId, elementId, value)
  -> Orchestrator
  -> PC Agent
  -> SetUiElementValueTool
  -> PermissionAuthorizer(write)
  -> current WindowDiscovery and inspected-element validation
  -> UiAutomation.setValue
  -> fresh COM re-resolution and identity validation
  -> IUIAutomationValuePattern.SetValue
```

No model provider participates. Events are `ui.value.requested`,
`ui.value.started`, and either `ui.value.succeeded` or `ui.value.failed`.
They contain operation, target IDs, success/failure, and sanitized error
metadata only. The submitted value is never placed in an event or error log.

Milestone 3C.1 adds two deterministic Browser Agent routes:

```text
DiscoverChromeProfilesCommand
  -> Orchestrator -> BrowserAgent -> DiscoverChromeProfilesTool
  -> PermissionAuthorizer(read) -> ChromeProfileRegistry

LaunchChromeProfileCommand(profileId)
  -> Orchestrator -> BrowserAgent -> LaunchChromeProfileTool
  -> PermissionAuthorizer(execute) -> ChromeLauncher
  -> ChromeProfileRegistry + ChromeInstallationResolver
  -> direct Windows process start -> BrowserSession selected profile
```

Neither route consults `ModelProvider`. Discovery emits
`chrome.profile.discovery.requested/started/succeeded/failed`; launch emits
the corresponding `chrome.profile.launch.*` lifecycle. Events contain counts,
opaque profile IDs, safe display names, success, and error codes only—never
profile paths, cookies, tokens, history, or credentials.

## Agent and tool relationship

An agent exposes the tools available to its responsibility and handles an
`AgentRequest`. A tool has a stable ID, descriptive metadata, an AI-callable
input schema, required permissions, and structured output. `AuthorizedTool`
checks every requested permission before calling a concrete operation. The PC
Agent performs no natural-language parsing; it accepts
`LaunchApplicationAgentRequest` and exposes only its configured tools.

## Window model and discovery

`WindowInfo` is the platform-neutral desktop snapshot. It contains a runtime
ID, title, process ID, optional process/application identifiers, visibility,
minimized/maximized state, and active state. Its public contract contains no
HWND, HANDLE, or other Windows-specific type.

`WindowDiscovery` returns structured `Result` values from `listWindows()` and
`getActiveWindow()`. `ListWindowsTool` and `GetActiveWindowTool` translate those
models into structured tool output and require `read` permission.

`WindowsWindowDiscovery` is the only Win32 implementation. Through Dart FFI it
uses `EnumWindows`, `GetForegroundWindow`, visibility/window-state APIs,
`GetWindowTextW`, `GetWindowThreadProcessId`, and
`QueryFullProcessImageNameW`. It opens process handles with query-only access
and closes every handle. Failure to read one process name leaves that optional
field null; it does not fail the entire enumeration.

Enumeration is limited to visible, titled top-level windows. It uses no screen
capture, OCR, shell, PowerShell, external utility, or filesystem scan. The
small Dart-team `ffi` package supplies native allocation and UTF-16 helpers;
it is not an automation framework.

## Window control and runtime identity

`WindowController` is platform-neutral and exposes activate, minimize,
maximize, restore, and close operations using a runtime window ID. It returns a
structured receipt or failure and exposes no HWND type.

`WindowsWindowController` accepts IDs in the discovery-generated
`windows:window:<hex>` form, but never trusts the encoded handle by itself. For
every operation it obtains a fresh `WindowDiscovery` snapshot, requires an
exact ID match, parses the handle only after that match, and verifies it again
with `IsWindow`. A stale or invented ID returns `window_not_found` or
`invalid_window_id`.

The native implementation uses `SetForegroundWindow` for activation,
`ShowWindow` with the single requested state for minimize/maximize/restore, and
`PostMessageW(WM_CLOSE)` for a normal close request. It does not call a process
termination API, inject input, invoke a shell, or run an external utility.

## UI element model and generic automation boundary

`UiElement` is a platform-neutral snapshot containing an opaque, inspection-
scoped runtime ID, optional parent ID, name, automation ID, common control type,
class name, enabled/visible/focused/password state, Value read-only state,
depth, and discovered pattern names.
Element IDs look like `uia:<session>:<ordinal>` and deliberately do not expose
COM pointers, UIA runtime arrays, or HWND values.

Common control types include window, button, edit, text, menu/menu item,
tab/tab item, list/list item, combo box, check box, radio button, image,
hyperlink, tree/tree item, slider, and progress bar. Unrepresented Windows
types map to `unknown` instead of failing inspection.

`UiPattern` represents discoverable capability metadata only: Invoke, Value,
Text, Selection, SelectionItem, Toggle, ExpandCollapse, Scroll, and RangeValue.
Only Invoke and Value are executable; all other pattern names are discovery
metadata.

`UiAutomation` exposes bounded window inspection plus root, children, element,
and query operations over the last inspection snapshot. It is generic and
application-neutral: it has no browser, Chrome, website, or product-specific
selector logic.

`UiAutomation.invoke(windowId, elementId)` and
`UiAutomation.setValue(windowId, elementId, value)` are its action operations.
SetValue returns a platform-neutral `UiSetValueReceipt` and exposes no entered
text in that receipt. It is bounded to 1,048,576 UTF-16 code units so isolate
messages and native BSTR allocations fail safely for pathological inputs
without restricting ordinary text. Invoke returns a platform-neutral
`UiInvokeReceipt`; no COM interface or native address crosses the boundary.
Invoke requires `execute`; SetValue requires `write`.

## Windows UI Automation implementation

`WindowsUiAutomation` first validates the target against current
`WindowDiscovery`, then runs all native traversal in `Isolate.run` so a large or
slow provider does not synchronously occupy Flutter's UI isolate. The worker:

1. initializes COM for its own multithreaded apartment with `CoInitializeEx`;
2. creates `CUIAutomation` through `CoCreateInstance`;
3. resolves the already-validated HWND with `ElementFromHandle`;
4. traverses the UI Automation control view through
   `IUIAutomationTreeWalker`; and
5. converts properties/pattern availability to plain Dart maps before crossing
   the isolate boundary.

Traversal is breadth-first and always constrained by caller-supplied
`maxDepth` and `maxElements`. Safe defaults are 3/100 and hard ceilings are
10/500. The adapter checks limits before native work and stops enqueueing COM
objects at the element cap. `wasTruncated` tells callers when either boundary
cut the tree short.

Every acquired UI Automation element, pattern, walker, and automation interface
is released through COM `Release`; every BSTR is freed with `SysFreeString`;
native allocations use scoped `calloc` cleanup; and COM is uninitialized on
the worker that initialized it. Property/provider failures degrade individual
values where safe, while initialization/root/traversal failures return
structured `Result.failure` values.

## Runtime identity and stale-element safety

Public element IDs remain opaque, inspection-scoped values such as
`uia:<session>:<ordinal>`. They are neither HWNDs, COM pointers, raw addresses,
nor reusable global selectors. The Windows adapter privately associates each
ID with:

- its target window ID;
- its control-view child-index path;
- the UI Automation runtime-ID integer array; and
- a semantic fingerprint: name, automation ID, class, and control type.

On Invoke, the adapter first validates the top-level window against a fresh
window snapshot. A new background COM worker resolves the window root, walks
the recorded path, obtains the current runtime ID and properties, and requires
an exact match. It then reacquires `UIA_InvokePatternId`, verifies support at
action time, calls `IUIAutomationInvokePattern::Invoke`, and releases every
interface. A missing mapping, changed path/runtime ID/fingerprint, missing
pattern, or provider error returns a structured failure. Successful IDs are
consumed, and every successful new inspection invalidates the previous
inspection's IDs.

This prevents a stale ordinal/path from silently targeting a replacement
element when the UI changes between inspection and action.

SetValue uses the same identity resolution and one-shot ID rules, so it cannot
weaken or bypass Invoke's stale-element protection. After a fresh match it
reacquires `UIA_ValuePatternId`, reads the Value pattern's current read-only
state, refuses unknown or read-only state, allocates a scoped BSTR, and calls
`SetValue`. The worker releases the Value pattern and all other COM interfaces,
frees the BSTR/native allocations, and uninitializes COM in every path.

## Application Registry and Windows launcher

`ApplicationDescriptor` gives every launchable program a stable ID, display
name, resolution strategy, and known executable locations. The local
`ApplicationRegistry` supports registration, lookup, listing, and resolution.

`WindowsApplicationRegistry` registers Chrome, Edge, Notepad, Calculator, File
Explorer, Windows Settings, and Task Manager. It checks only fixed executable
locations below `ProgramFiles`, `ProgramFiles(x86)`, `LOCALAPPDATA`, and
`SystemRoot`. It does not crawl the filesystem or accept user-supplied paths.

`ApplicationLauncher` separates process creation from lookup and tools. Its
Windows implementation receives a resolved descriptor, starts that executable
directly with an empty argument list and `runInShell: false`, and returns a
structured launch receipt. Tests replace this boundary with a mock launcher.

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

## Chrome profile and Browser Agent foundation

`ChromeProfile` contains an opaque runtime ID, metadata-derived display name,
Chrome directory identifier, optional safe avatar identifier, and default
indicator. Directory identifiers such as `Default` and `Profile 1` are never
interpreted as Personal or Work; only Chrome's actual metadata supplies the
display name.

`WindowsChromeProfileRegistry` reads the standard current-user
`LOCALAPPDATA\\Google\\Chrome\\User Data\\Local State` JSON. It does not scan
the drive, recurse through directories, scrape Chrome UI, invoke a shell, or
require Chrome to be running. It reads `profile.info_cache`, respects
`profiles_order`, checks only the named immediate profile directory, skips an
individually malformed/inaccessible entry, and returns structured failures for
missing or malformed global metadata. IDs have the form
`chrome_profile_<opaque-runtime-hash>` and remain stable for the registry
instance. Callers cannot submit directory identifiers to launch APIs.

`WindowsChromeInstallationResolver` reuses the allow-listed application
registry's known Program Files and per-user Chrome locations and additionally
requires a resolved `chrome.exe`. `WindowsChromeLauncher` accepts only an
opaque profile ID, resolves it through the populated registry, resolves the
executable independently, internally creates exactly
`--profile-directory=<validated discovered identifier>`, and starts the
executable directly with `runInShell: false`. It accepts no caller path,
directory, argument list, or shell fragment.

`BrowserSession` stores the selected `ChromeProfile` after a successful launch.
The minimal `BrowserAgent` owns these profile routes separately from PC Agent
and generic Windows UI Automation. Reliable automatic confirmation of which
already-running Chrome window belongs to the new process is not available in
this foundation, so verification reports the validated selected profile and
process launch rather than guessing from windows.

Navigation, tabs, search, websites, DOM/CDP integration, and page interaction
are FUTURE / NOT IMPLEMENTED.

## Security boundary

Permissions are `read`, `write`, `execute`, and `sensitive`. A tool declares
what it needs; `AuthorizedTool` submits a `PermissionRequest` before concrete
execution. Launching Chrome requires `execute`, not `sensitive`. Resolution and
process creation happen only after authorization succeeds. The current
allow-list policy is deliberately small and local.
Window discovery requires only `read`; native enumeration is not invoked when
authorization is denied.
Activation, minimize, maximize, and restore require `execute`. Close requires
`sensitive`, which is deliberately absent from `AppConfiguration.defaults()`.
The manual close command grants it only after confirming that the freshly
discovered target is `notepad.exe` and the explicit test flag is present.
UI inspection also requires `read`. `InspectUiTool` validates its input before
authorization, then performs fresh window validation after authorization; the
native adapter validates again before decoding the window handle. No COM
inspection occurs when permission is denied.
Semantic Invoke is an action and requires `execute`. `InvokeUiElementTool`
validates both IDs before authorization; discovery, element checks, and COM
Invoke occur only after authorization. The window ID is mandatory so an
element mapping cannot be used against another window.
Semantic SetValue is a write operation and requires `write`, which is not
silently added to `AppConfiguration.defaults()`. The manual development utility
creates a scoped read/write configuration only for its explicit test flow.
Authorization occurs before discovery, element resolution, or COM SetValue.
Value lifecycle events are projected from target IDs and operation metadata;
neither success nor failure events receive the submitted text, and failure
messages are sanitized.
Chrome profile discovery requires `read`; metadata access occurs only after
authorization. Profile-aware Chrome launch requires `execute`; profile
resolution, executable resolution, process creation, and BrowserSession update
occur only after authorization. The APIs expose no arbitrary executable,
directory, argument, shell, PowerShell, or cmd execution surface.
Future consent prompts, audit logs, resource scopes, and persistent policies
can implement `PermissionAuthorizer` without allowing tools to bypass it.

## Configuration and memory

`AppConfiguration` holds the provider selection, optional local-model settings,
permissions, feature flags, and storage locations. It is local and injected at
startup. `MemoryStore` supplies store/retrieve/delete operations; the current
implementation is volatile and intentionally has no vector or cloud backend.

## Current limitations

Only generic/profile-aware Chrome launch, Chrome profile discovery and selected
session profile state, window discovery/control, bounded UI discovery, Invoke,
and Value/SetValue are implemented. Selection, Toggle, ExpandCollapse, Scroll,
RangeValue, and Text actions are not implemented. There is no navigation, screenshot/OCR,
browser-specific control, keyboard/mouse input, arbitrary process/terminal
execution, process termination, or persistent element reference. Provider-
driven execution, other semantic actions, and non-Windows automation remain
future work.
