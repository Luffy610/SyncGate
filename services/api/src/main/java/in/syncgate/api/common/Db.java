package in.syncgate.api.common;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

/** Small helpers so timestamps and UUIDs round-trip the same on H2 and PostgreSQL. */
public final class Db {

    private Db() {}

    public static OffsetDateTime ts(Instant instant) {
        return instant == null ? null : OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }

    public static Instant instant(ResultSet rs, String column) throws SQLException {
        OffsetDateTime value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : AppClock.millis(value.toInstant());
    }

    public static UUID uuid(ResultSet rs, String column) throws SQLException {
        return rs.getObject(column, UUID.class);
    }

    public static Integer integer(ResultSet rs, String column) throws SQLException {
        int value = rs.getInt(column);
        return rs.wasNull() ? null : value;
    }

    public static Double decimal(ResultSet rs, String column) throws SQLException {
        double value = rs.getDouble(column);
        return rs.wasNull() ? null : value;
    }

    /** Parses a path or body id, answering 404 instead of a 500 for garbage. */
    public static UUID parseId(String text) {
        try {
            return UUID.fromString(text);
        } catch (IllegalArgumentException | NullPointerException e) {
            throw ApiException.notFound("Record");
        }
    }
}
