import 'package:flutter/material.dart';

extension PhoneAgentThemeColors on BuildContext {
  PhoneAgentColors get phoneAgentColors =>
      Theme.of(this).extension<PhoneAgentColors>() ?? PhoneAgentColors.light;
}

@immutable
class PhoneAgentColors extends ThemeExtension<PhoneAgentColors> {
  const PhoneAgentColors._(this._values);

  static final PhoneAgentColors light = PhoneAgentColors._(_lightValues);

  final Map<String, Color> _values;

  Color _color(String key) => _values[key]!;

  Color get pageBackground => _color('pageBackground');
  Color get panelBackground => _color('panelBackground');
  Color get cardBackground => _color('cardBackground');
  Color get cardSelectedBackground => _color('cardSelectedBackground');
  Color get border => _color('border');
  Color get textPrimary => _color('textPrimary');
  Color get textSecondary => _color('textSecondary');
  Color get textTertiary => _color('textTertiary');
  Color get primaryAction => _color('primaryAction');
  Color get primaryActionDisabled => _color('primaryActionDisabled');
  Color get iconButtonBackground => _color('iconButtonBackground');
  Color get composerSurface => _color('composerSurface');
  Color get inputBackground => _color('inputBackground');
  Color get inputBackgroundActive => _color('inputBackgroundActive');
  Color get inputHint => _color('inputHint');
  Color get outgoingBubbleBackground => _color('outgoingBubbleBackground');
  Color get incomingBubbleBackground => _color('incomingBubbleBackground');
  Color get incomingBubbleBorder => _color('incomingBubbleBorder');
  Color get messageText => _color('messageText');
  Color get outgoingMessageText => _color('outgoingMessageText');
  Color get statusBackground => _color('statusBackground');
  Color get statusText => _color('statusText');
  Color get warningBackground => _color('warningBackground');

  @override
  PhoneAgentColors copyWith({Map<String, Color>? values}) {
    return PhoneAgentColors._({..._values, if (values != null) ...values});
  }

  @override
  PhoneAgentColors lerp(ThemeExtension<PhoneAgentColors>? other, double t) {
    if (other is! PhoneAgentColors) {
      return this;
    }
    return PhoneAgentColors._({
      for (final key in _values.keys)
        key: Color.lerp(_values[key], other._values[key], t) ?? _values[key]!,
    });
  }
}

const Map<String, Color> _lightValues = {
  'pageBackground': Color(0xFFF3F4F7),
  'panelBackground': Color(0xFFF6F7F8),
  'cardBackground': Color(0xFFFFFFFF),
  'cardSelectedBackground': Color(0xFFE8F4FB),
  'border': Color(0xFFD7E0EB),
  'textPrimary': Color(0xFF151B26),
  'textSecondary': Color(0xFF6E7A88),
  'textTertiary': Color(0xFFA1A9B3),
  'primaryAction': Color(0xFF169AF3),
  'primaryActionDisabled': Color(0xFF8FD3FF),
  'iconButtonBackground': Color(0xFFFFFFFF),
  'composerSurface': Color(0xFFF6F6F6),
  'inputBackground': Color(0xFFFEFEFF),
  'inputBackgroundActive': Color(0xFFFFFFFF),
  'inputHint': Color(0xFFACB3BD),
  'outgoingBubbleBackground': Color(0xFF169AF3),
  'incomingBubbleBackground': Color(0xFFFFFFFF),
  'incomingBubbleBorder': Color(0xFFE7ECF2),
  'messageText': Color(0xFF262B31),
  'outgoingMessageText': Color(0xFFFFFFFF),
  'statusBackground': Color(0xFFE8F4FB),
  'statusText': Color(0xFF2578B8),
  'warningBackground': Color(0xFFFFF4F1),
};
