import '../../core/result.dart';

enum BrowserLoadingState { idle, loading, completed }

final class BrowserControllerState {
  const BrowserControllerState({
    required this.isInitialized,
    required this.loadingState,
    this.currentUrl,
    this.title,
    this.canGoBack = false,
    this.canGoForward = false,
    this.navigationFailure,
  });

  const BrowserControllerState.uninitialized()
    : this(isInitialized: false, loadingState: BrowserLoadingState.idle);

  final bool isInitialized;
  final BrowserLoadingState loadingState;
  final Uri? currentUrl;
  final String? title;
  final bool canGoBack;
  final bool canGoForward;
  final Failure? navigationFailure;
}

abstract interface class BrowserController {
  Stream<BrowserControllerState> get states;
  BrowserControllerState get state;

  Future<Result<void>> initialize();
  Future<Result<void>> navigate(Uri url);
  Future<Result<void>> goBack();
  Future<Result<void>> goForward();
  Future<Result<void>> reload();
  Future<Result<Uri?>> getCurrentUrl();
  Future<Result<String?>> getTitle();
  Future<Result<void>> dispose();
}

final class EmbeddedBrowserUrlPolicy {
  const EmbeddedBrowserUrlPolicy._();

  static Result<Uri> validate(Uri url) {
    if ((url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      return const Result.failure(
        Failure(
          'Only absolute HTTP and HTTPS browser addresses are supported.',
          code: 'invalid_url',
        ),
      );
    }
    return Result.success(url);
  }
}

