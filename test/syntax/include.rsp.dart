//Auto-generated by RSP Compiler
//Source: include.rsp.html
library include_rsp;

import 'dart:async';
import 'dart:io';
import 'package:stream/stream.dart';

/** Template, include, for rendering the view. */
Future include(HttpConnect connect, {foo, more, less}) async {
  HttpResponse response = connect.response;
  if (!Rsp.init(connect, "text/html; charset=utf-8"))
    return null;

  final _less_ = new StringBuffer();
  final _0 = connect;
  connect = new HttpConnect.stringBuffer(connect, _less_);
  response = connect.response;

  response.write("""less is more
""");

  connect = _0;
  response = connect.response;
  final less = _less_.toString();

  response.write("""

""");

  final _1 = new StringBuffer();
  final _2 = connect;
  connect = new HttpConnect.stringBuffer(connect, _1);
  response = connect.response;

  response.write("""  More information
""");

  await include(new HttpConnect.chain(connect), more: "recursive");

  connect = _2;
  response = connect.response;

  await include(new HttpConnect.chain(connect), foo: true, less: less, more: _1.toString());

  return null;
}
