import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veloxmd/services/link_resolver.dart';

void main() {
  group('LinkResolver.resolve', () {
    late Directory tempDir;
    late String current;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('veloxmd_links_');
      current = p.join(tempDir.path, 'a.md');
      await File(current).writeAsString('# A');
      await File(p.join(tempDir.path, 'b.md')).writeAsString('# B');
      await File(p.join(tempDir.path, 'my doc.md')).writeAsString('# Spaced');
      await Directory(p.join(tempDir.path, 'sub')).create();
      await File(p.join(tempDir.path, 'sub', 'c.markdown')).writeAsString('# C');
      await File(p.join(tempDir.path, 'image.png')).writeAsBytes([0]);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<LinkTarget> resolve(String href, {String? from}) =>
        LinkResolver.resolve(href, currentPath: from ?? current);

    test('fragment-only link is an anchor in the current document', () async {
      final target = await resolve('#Getting-Started');
      expect(target, isA<AnchorTarget>());
      expect((target as AnchorTarget).anchor, 'getting-started');
    });

    test('anchor is URL-decoded', () async {
      final target = await resolve('#caf%C3%A9') as AnchorTarget;
      expect(target.anchor, 'café');
    });

    test('relative link to an existing document', () async {
      final target = await resolve('b.md') as DocumentTarget;
      expect(target.path, p.join(tempDir.path, 'b.md'));
      expect(target.anchor, isNull);
    });

    test('relative link with anchor', () async {
      final target = await resolve('./b.md#Setup') as DocumentTarget;
      expect(target.path, p.join(tempDir.path, 'b.md'));
      expect(target.anchor, 'setup');
    });

    test('resolves against the current document directory', () async {
      final from = p.join(tempDir.path, 'sub', 'c.markdown');
      final target = await resolve('../b.md', from: from) as DocumentTarget;
      expect(target.path, p.join(tempDir.path, 'b.md'));
    });

    test('subdirectory and percent-encoded paths', () async {
      expect(
        (await resolve('sub/c.markdown') as DocumentTarget).path,
        p.join(tempDir.path, 'sub', 'c.markdown'),
      );
      expect(
        (await resolve('my%20doc.md') as DocumentTarget).path,
        p.join(tempDir.path, 'my doc.md'),
      );
    });

    test('absolute path and file:// URI', () async {
      final b = p.join(tempDir.path, 'b.md');
      expect((await resolve(b) as DocumentTarget).path, b);
      final fromUri =
          await resolve('${Uri.file(b)}#intro') as DocumentTarget;
      expect(fromUri.path, b);
      expect(fromUri.anchor, 'intro');
    });

    test('query string is ignored for local paths', () async {
      expect(await resolve('b.md?plain=1'), isA<DocumentTarget>());
    });

    test('link to self with anchor is an anchor target', () async {
      final target = await resolve('a.md#Intro');
      expect(target, isA<AnchorTarget>());
      expect((target as AnchorTarget).anchor, 'intro');
    });

    test('missing document is unreachable', () async {
      expect(await resolve('missing.md'), isA<UnreachableTarget>());
      expect(await resolve('missing.md#x'), isA<UnreachableTarget>());
    });

    test('existing non-document file and directory are external', () async {
      final image = await resolve('image.png') as ExternalTarget;
      expect(image.uri, Uri.file(p.join(tempDir.path, 'image.png')));
      expect(await resolve('sub'), isA<ExternalTarget>());
    });

    test('web and mail links are external', () async {
      final web = await resolve('https://example.com/x#y') as ExternalTarget;
      expect(web.uri.toString(), 'https://example.com/x#y');
      expect(await resolve('HTTP://example.com'), isA<ExternalTarget>());
      expect(await resolve('mailto:a@b.c'), isA<ExternalTarget>());
    });

    test('unsupported schemes and empty links are unreachable', () async {
      expect(await resolve('ftp://example.com/a.md'), isA<UnreachableTarget>());
      expect(await resolve('javascript:alert(1)'), isA<UnreachableTarget>());
      expect(await resolve(''), isA<UnreachableTarget>());
      expect(await resolve('#'), isA<UnreachableTarget>());
    });
  });
}
