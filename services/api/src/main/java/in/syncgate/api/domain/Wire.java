package in.syncgate.api.domain;

import in.syncgate.api.common.ApiException;

/**
 * Wire format of the enums shared with the Flutter app: Java constants are
 * UPPER_SNAKE, JSON and the database use the Dart names (lowerCamel), e.g.
 * {@code GATE_OPERATOR} is {@code "gateOperator"}.
 */
public final class Wire {

    private Wire() {}

    public static String of(Enum<?> value) {
        String[] parts = value.name().toLowerCase().split("_");
        StringBuilder out = new StringBuilder(parts[0]);
        for (int i = 1; i < parts.length; i++) {
            out.append(Character.toUpperCase(parts[i].charAt(0))).append(parts[i].substring(1));
        }
        return out.toString();
    }

    public static <E extends Enum<E>> E parse(Class<E> type, String text) {
        if (text != null) {
            for (E candidate : type.getEnumConstants()) {
                if (of(candidate).equals(text)) {
                    return candidate;
                }
            }
        }
        throw ApiException.invalid("Unknown " + type.getSimpleName() + " value");
    }

    public static <E extends Enum<E>> E parseOrNull(Class<E> type, String text) {
        return text == null ? null : parse(type, text);
    }
}
