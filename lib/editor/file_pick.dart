// Choosing a file on the device the page is open on, and sending it. Only a
// browser can; anywhere else (tests, the TV) there is the stand-in.
export 'file_pick_stub.dart' if (dart.library.js_interop) 'file_pick_web.dart';
