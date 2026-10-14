/// The paired session token, kept per browser. Backed by `localStorage` on
/// the web and by nothing off it (tests).
library;

export 'token_store_stub.dart'
    if (dart.library.js_interop) 'token_store_web.dart';
