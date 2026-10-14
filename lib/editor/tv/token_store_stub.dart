/// Off the web (tests) the token lives only for the run.
String? _token;

String? loadToken() => _token;

void saveToken(String? token) => _token = token;
