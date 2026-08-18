import 'dart:async';

import 'package:flutter/material.dart';

import '../../browser/embedded/browser_controller.dart';

typedef BrowserSurfaceBuilder =
    Widget Function(BuildContext context, BrowserController controller);

final class CronyxBrowserPalette {
  const CronyxBrowserPalette({
    required this.background,
    required this.panel,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.accent,
    required this.error,
  });

  final Color background;
  final Color panel;
  final Color border;
  final Color borderStrong;
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color accent;
  final Color error;
}

/// Visual-only browser workspace. All mutations leave this widget through
/// callbacks and are routed by the shell through the Orchestrator.
class CronyxBrowserWorkspace extends StatefulWidget {
  const CronyxBrowserWorkspace({
    required this.controller,
    required this.surfaceBuilder,
    required this.palette,
    required this.onNavigate,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    super.key,
  });

  final BrowserController controller;
  final BrowserSurfaceBuilder surfaceBuilder;
  final CronyxBrowserPalette palette;
  final Future<void> Function(Uri url) onNavigate;
  final Future<void> Function() onBack;
  final Future<void> Function() onForward;
  final Future<void> Function() onReload;

  @override
  State<CronyxBrowserWorkspace> createState() => _CronyxBrowserWorkspaceState();
}

class _CronyxBrowserWorkspaceState extends State<CronyxBrowserWorkspace> {
  final TextEditingController _address = TextEditingController();
  StreamSubscription<BrowserControllerState>? _subscription;
  late BrowserControllerState _state;
  String? _addressError;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _subscription = widget.controller.states.listen(_handleState);
  }

  @override
  void didUpdateWidget(CronyxBrowserWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    unawaited(_subscription?.cancel());
    _state = widget.controller.state;
    _subscription = widget.controller.states.listen(_handleState);
  }

  void _handleState(BrowserControllerState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      final current = state.currentUrl?.toString();
      if (current != null && current != _address.text) {
        _address.text = current;
        _address.selection = TextSelection.collapsed(offset: current.length);
      }
    });
  }

  Future<void> _submitAddress(String raw) async {
    final parsed = Uri.tryParse(raw.trim());
    final validated = parsed == null
        ? null
        : EmbeddedBrowserUrlPolicy.validate(parsed);
    final url = validated?.fold<Uri?>((value) => value, (_) => null);
    if (url == null) {
      setState(() => _addressError = 'Enter an absolute HTTP or HTTPS URL');
      return;
    }
    setState(() => _addressError = null);
    await widget.onNavigate(url);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final title = _state.title?.trim();
    final displayTitle = title == null || title.isEmpty ? 'New tab' : title;
    return Material(
      key: const Key('browser-workspace'),
      color: palette.background,
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                key: const Key('browser-active-tab'),
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: palette.background,
                  border: Border.all(color: palette.border),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(9),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 14, color: palette.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                _ToolbarButton(
                  key: const Key('browser-back'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  color: palette.secondary,
                  onPressed: _state.canGoBack ? widget.onBack : null,
                ),
                _ToolbarButton(
                  key: const Key('browser-forward'),
                  icon: Icons.arrow_forward_rounded,
                  tooltip: 'Forward',
                  color: palette.secondary,
                  onPressed: _state.canGoForward ? widget.onForward : null,
                ),
                _ToolbarButton(
                  key: const Key('browser-reload'),
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reload',
                  color: palette.secondary,
                  onPressed: _state.isInitialized ? widget.onReload : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('browser-address-input'),
                    controller: _address,
                    enabled: _state.isInitialized,
                    onSubmitted: _submitAddress,
                    textInputAction: TextInputAction.go,
                    style: TextStyle(color: palette.primary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _state.isInitialized
                          ? 'https://example.com'
                          : 'Initializing CronyX Browser…',
                      hintStyle: TextStyle(color: palette.muted, fontSize: 12),
                      errorText: _addressError,
                      errorStyle: TextStyle(color: palette.error, fontSize: 9),
                      filled: true,
                      fillColor: palette.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: palette.borderStrong),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_state.loadingState == BrowserLoadingState.loading)
            LinearProgressIndicator(
              key: const Key('browser-loading'),
              minHeight: 2,
              color: palette.accent,
              backgroundColor: palette.background,
            ),
          Expanded(
            child: _state.isInitialized
                ? ClipRect(
                    child: widget.surfaceBuilder(context, widget.controller),
                  )
                : Center(
                    child: Text(
                      'CRONYX BROWSER',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed == null ? null : () => unawaited(onPressed!()),
    icon: Icon(icon),
    tooltip: tooltip,
    iconSize: 18,
    color: color,
    disabledColor: color.withValues(alpha: .3),
    visualDensity: VisualDensity.compact,
  );
}
