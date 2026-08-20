import 'dart:async';

import 'package:flutter/material.dart';

import '../../browser/embedded/browser_controller.dart';
import '../../browser/embedded/windows_webview2_browser_controller.dart';
import '../../core/result.dart';

final class CronyxBrowserPrototype extends StatefulWidget {
  const CronyxBrowserPrototype({super.key, this.demonstrationUrl});

  final String? demonstrationUrl;

  @override
  State<CronyxBrowserPrototype> createState() => _CronyxBrowserPrototypeState();
}

final class _CronyxBrowserPrototypeState extends State<CronyxBrowserPrototype> {
  final WindowsWebView2BrowserController _controller =
      WindowsWebView2BrowserController();
  StreamSubscription<BrowserControllerState>? _stateSubscription;
  BrowserControllerState _browserState =
      const BrowserControllerState.uninitialized();
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _controller.states.listen((state) {
      if (mounted) setState(() => _browserState = state);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final initialization = await _controller.initialize();
    if (initialization case Failed<void>(:final failure)) {
      if (mounted) setState(() => _error = failure.message);
      return;
    }
    final navigation = await _controller.navigate(
      Uri.parse('https://example.com'),
    );
    if (navigation case Failed<void>(:final failure)) {
      if (mounted) setState(() => _error = failure.message);
      return;
    }
    final demonstrationUrl = widget.demonstrationUrl;
    if (demonstrationUrl != null) {
      await _waitForCompletedHost('example.com');
      final result = await _controller.navigate(Uri.parse(demonstrationUrl));
      if (result case Failed<void>(:final failure)) {
        if (mounted) setState(() => _error = failure.message);
      }
    }
  }

  Future<void> _waitForCompletedHost(String host) async {
    bool isCompleted(BrowserControllerState state) =>
        state.currentUrl?.host == host &&
        state.loadingState == BrowserLoadingState.completed;
    if (isCompleted(_controller.state)) return;
    await _controller.states.firstWhere(isCompleted);
  }

  Future<void> _navigateToFlutter() async {
    final result = await _controller.navigate(Uri.parse('https://flutter.dev'));
    if (result case Failed<void>(:final failure)) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CronyX Personal Browser Prototype'),
        actions: [
          TextButton(
            onPressed: _browserState.isInitialized ? _navigateToFlutter : null,
            child: const Text('Navigate to flutter.dev'),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(_browserState.title ?? 'No page title yet'),
            subtitle: Text(
              _browserState.currentUrl?.toString() ?? 'No current URL yet',
            ),
            trailing: Text(_browserState.loadingState.name),
          ),
          if (_error case final error?)
            Padding(padding: const EdgeInsets.all(16), child: Text(error)),
          Expanded(
            child: _browserState.isInitialized
                ? WindowsWebView2Surface(controller: _controller)
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

