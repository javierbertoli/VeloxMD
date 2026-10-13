import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloxmd/services/keybindings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('KeybindingsService includes exportPdf action with default shortcuts', () async {
    final keybindings = await KeybindingsService.load();

    expect(keybindings[KeyAction.exportPdf], isNotEmpty);
    expect(keybindings.label(KeyAction.exportPdf), equals('Ctrl+P'));
    expect(keybindings.labels(KeyAction.exportPdf), contains('Ctrl+P'));
  });

  test('history navigation defaults to Alt+Left / Alt+Right', () async {
    final keybindings = await KeybindingsService.load();

    expect(keybindings.label(KeyAction.navigateBack), 'Alt+Left');
    expect(keybindings.label(KeyAction.navigateForward), 'Alt+Right');
    final back = keybindings[KeyAction.navigateBack].single;
    expect(back.trigger, LogicalKeyboardKey.arrowLeft);
    expect(back.alt, isTrue);
  });
}
