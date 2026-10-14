import 'package:web/web.dart' as web;

const _key = 'openlauncher.token';

String? loadToken() {
  try {
    return web.window.localStorage.getItem(_key);
  } on Object {
    // Private windows can refuse storage.
    return null;
  }
}

void saveToken(String? token) {
  try {
    if (token == null) {
      web.window.localStorage.removeItem(_key);
    } else {
      web.window.localStorage.setItem(_key, token);
    }
  } on Object {
    // Nothing to do if storage is unavailable.
  }
}
