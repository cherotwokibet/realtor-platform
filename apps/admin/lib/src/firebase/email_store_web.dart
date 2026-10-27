import 'package:web/web.dart' as web;

const _key = 'adminSignInEmail';

String? readSignInEmail() {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void writeSignInEmail(String? email) {
  try {
    if (email == null) {
      web.window.localStorage.removeItem(_key);
    } else {
      web.window.localStorage.setItem(_key, email);
    }
  } catch (_) {
    // Private windows can refuse storage; the person types the email again.
  }
}
