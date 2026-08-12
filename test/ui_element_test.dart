import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';
import 'package:ai_os/tools/windows/ui_automation/windows_ui_automation_mappings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UiElement is platform-neutral and round-trips structured data', () {
    final element = UiElement(
      id: 'uia:session:1',
      parentId: 'uia:session:0',
      name: 'Submit',
      automationId: 'submit',
      controlType: UiControlType.button,
      className: 'Button',
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 1,
      supportedPatterns: const {UiPattern.invoke},
    );

    final restored = UiElement.fromMap(element.toMap());

    expect(restored.id, 'uia:session:1');
    expect(restored.parentId, 'uia:session:0');
    expect(restored.controlType, UiControlType.button);
    expect(restored.supportedPatterns, {UiPattern.invoke});
  });

  test('maps all required common Windows control types', () {
    expect(
      WindowsUiAutomationMappings.controlTypeFromId(50032),
      UiControlType.window,
    );
    expect(
      WindowsUiAutomationMappings.controlTypeFromId(50000),
      UiControlType.button,
    );
    expect(
      WindowsUiAutomationMappings.controlTypeFromId(50004),
      UiControlType.edit,
    );
    expect(
      WindowsUiAutomationMappings.controlTypeFromId(50018),
      UiControlType.tab,
    );
    expect(
      WindowsUiAutomationMappings.controlTypeFromId(99999),
      UiControlType.unknown,
    );
  });

  test('maps required pattern IDs and ignores unknown patterns', () {
    expect(WindowsUiAutomationMappings.patternFromId(10000), UiPattern.invoke);
    expect(WindowsUiAutomationMappings.patternFromId(10002), UiPattern.value);
    expect(WindowsUiAutomationMappings.patternFromId(10014), UiPattern.text);
    expect(WindowsUiAutomationMappings.patternFromId(10015), UiPattern.toggle);
    expect(WindowsUiAutomationMappings.patternFromId(99999), isNull);
  });
}
