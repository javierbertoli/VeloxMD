import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/models/navigation_history.dart';

void main() {
  group('NavigationHistory', () {
    test('starts empty', () {
      final history = NavigationHistory();
      expect(history.current, isNull);
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
      expect(history.back(), isNull);
      expect(history.forward(), isNull);
    });

    test('back and forward walk visited entries', () {
      final history = NavigationHistory()
        ..visit('a.md')
        ..visit('b.md')
        ..visit('c.md');

      expect(history.current!.path, 'c.md');
      expect(history.back()!.path, 'b.md');
      expect(history.back()!.path, 'a.md');
      expect(history.canGoBack, isFalse);
      expect(history.forward()!.path, 'b.md');
      expect(history.canGoForward, isTrue);
    });

    test('visiting after going back drops forward entries', () {
      final history = NavigationHistory()
        ..visit('a.md')
        ..visit('b.md')
        ..visit('c.md');
      history.back();
      history.visit('d.md');

      expect(history.canGoForward, isFalse);
      expect(history.length, 3);
      expect(history.back()!.path, 'b.md');
    });

    test('remembers the scroll offset of each entry', () {
      final history = NavigationHistory()..visit('a.md');
      history.updateCurrentScroll(120);
      history.visit('a.md'); // anchor jump within the same document
      history.updateCurrentScroll(900);

      expect(history.back()!.scrollOffset, 120);
      expect(history.forward()!.scrollOffset, 900);
    });
  });
}
