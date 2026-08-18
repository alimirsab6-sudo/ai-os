import 'package:ai_os/prototypes/personal_browser/cronyx_browser_prototype.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CronyxBrowserPrototype(demonstrationUrl: 'https://flutter.dev'),
    ),
  );
}
