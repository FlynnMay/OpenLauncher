import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A file on the TV; a URL in the browser.
ImageProvider pictureAt(String source) =>
    kIsWeb ? NetworkImage(source) : FileImage(File(source)) as ImageProvider;
