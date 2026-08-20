import 'ui_element.dart';

final class WindowsUiAutomationMappings {
  const WindowsUiAutomationMappings._();

  static UiControlType controlTypeFromId(int id) => switch (id) {
    50000 => UiControlType.button,
    50002 => UiControlType.checkBox,
    50003 => UiControlType.comboBox,
    50004 => UiControlType.edit,
    50005 => UiControlType.hyperlink,
    50006 => UiControlType.image,
    50007 => UiControlType.list,
    50008 => UiControlType.listItem,
    50009 || 50010 => UiControlType.menu,
    50011 => UiControlType.menuItem,
    50012 => UiControlType.progressBar,
    50013 => UiControlType.radioButton,
    50015 => UiControlType.slider,
    50018 => UiControlType.tab,
    50019 => UiControlType.tabItem,
    50020 => UiControlType.text,
    50023 => UiControlType.tree,
    50024 => UiControlType.treeItem,
    50032 => UiControlType.window,
    _ => UiControlType.unknown,
  };

  static UiPattern? patternFromId(int id) => switch (id) {
    10000 => UiPattern.invoke,
    10001 => UiPattern.selection,
    10002 => UiPattern.value,
    10003 => UiPattern.rangeValue,
    10004 => UiPattern.scroll,
    10005 => UiPattern.expandCollapse,
    10007 => UiPattern.selectionItem,
    10014 => UiPattern.text,
    10015 => UiPattern.toggle,
    _ => null,
  };

  static const patternIds = <int>[
    10000,
    10001,
    10002,
    10003,
    10004,
    10005,
    10007,
    10014,
    10015,
  ];
}

