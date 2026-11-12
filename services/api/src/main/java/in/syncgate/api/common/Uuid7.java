package in.syncgate.api.common;

import java.security.SecureRandom;
import java.util.UUID;

/** Time-ordered UUIDs (ADR-0011): sortable, unique across devices. */
public final class Uuid7 {

    private static final SecureRandom RANDOM = new SecureRandom();

    private Uuid7() {}

    public static UUID next() {
        return next(System.currentTimeMillis());
    }

    public static UUID next(long epochMillis) {
        byte[] r = new byte[10];
        RANDOM.nextBytes(r);
        long msb = (epochMillis & 0xFFFFFFFFFFFFL) << 16;
        msb |= 0x7000L | ((r[0] & 0x0FL) << 8) | (r[1] & 0xFFL);
        long lsb = 0L;
        for (int i = 2; i < 10; i++) {
            lsb = (lsb << 8) | (r[i] & 0xFFL);
        }
        lsb = (lsb & 0x3FFFFFFFFFFFFFFFL) | 0x8000000000000000L;
        return new UUID(msb, lsb);
    }
}
