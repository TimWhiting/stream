//Auto-generated by RSP Compiler
//Source: lastModified2.rsp.html
library lastModified2_rsp;

import 'dart:async';
import 'dart:io';
import 'package:stream/stream.dart';

/** Template, lastModified2, for rendering the view. */
Future lastModified2(HttpConnect connect) async {
  HttpResponse response = connect.response;
  if (!Rsp.init(connect, "text/html; charset=utf-8",
  lastModified: connect.channel.startedSince))
    return null;

  response.write("""<html>
  <head>
    <title></title>
  </head>
  <body>
  </body>
</html>
""");

  return null;
}
