//Auto-generated by RSP Compiler
//Source: lastModified2.rsp.html
library lastModified2_rsp;

import 'dart:async';
import 'dart:io';
import 'package:stream/stream.dart';

/** Template, lastModified2, for rendering the view. */
Future lastModified2(HttpConnect connect) { //#2
  var _t0_, _cs_ = new List<HttpConnect>();
  HttpRequest request = connect.request;
  HttpResponse response = connect.response;

  if (!connect.isIncluded)
    response.headers.contentType = ContentType.parse("text/html; charset=utf-8");
  response.headers.set(HttpHeaders.LAST_MODIFIED, connect.server.startedSince);

  response.write("""<html>
  <head>
    <title></title>
  </head>
  <body>
  </body>
</html>
"""); //#2

  return Rsp.nnf();
}
