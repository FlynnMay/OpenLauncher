import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The picture at [source]: a file on the TV, or in the browser, where the
/// same widgets draw the editor's replica, the address the TV serves it at.
ImageProvider pictureAt(String source) =>
    kIsWeb ? NetworkImage(source) : FileImage(File(source)) as ImageProvider;
