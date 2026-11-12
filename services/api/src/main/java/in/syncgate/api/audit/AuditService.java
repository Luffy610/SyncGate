package in.syncgate.api.audit;

import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.ChainService;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The audit log (FR-ADM-03): every sensitive action appends one hash-chained
 * row. Rows are never updated or deleted; {@link #verify()} proves it.
 */
@Service
public class AuditService {

    public static final String CHAIN = "audit";

    public record Entry(Instant at, String actor, String action, String detail) {}

    public record Verification(boolean ok, long checked, Long brokenAtSeq) {}

    private final JdbcClient jdbc;
    private final ChainService chain;
    private final AppClock clock;

    public AuditService(JdbcClient jdbc, ChainService chain, AppClock clock) {
        this.jdbc = jdbc;
        this.chain = chain;
        this.clock = clock;
    }

    /** Appends inside the caller's transaction, or starts one if there is none. */
    @Transactional(propagation = Propagation.REQUIRED)
    public void record(String actor, String action, String detail) {
        UUID id = Uuid7.next();
        Instant at = clock.now();
        ChainService.Link link = chain.reserve(CHAIN);
        String a = clip(actor, 80);
        String act = clip(action, 80);
        String det = clip(detail, 500);
        String hash = hash(link.prevHash(), id, at, a, act, det);
        jdbc.sql("""
                INSERT INTO audit_log (seq, id, at, actor, action, detail, prev_hash, hash)
                VALUES (:seq, :id, :at, :actor, :action, :detail, :prev, :hash)""")
                .param("seq", link.seq())
                .param("id", id)
                .param("at", Db.ts(at))
                .param("actor", a)
                .param("action", act)
                .param("detail", det)
                .param("prev", link.prevHash())
                .param("hash", hash)
                .update();
        chain.commit(CHAIN, link.seq(), hash);
    }

    public List<Entry> latest(int limit) {
        int capped = Math.max(1, Math.min(limit, 500));
        return jdbc.sql("SELECT at, actor, action, detail FROM audit_log ORDER BY seq DESC LIMIT :n")
                .param("n", capped)
                .query((rs, i) -> new Entry(Db.instant(rs, "at"), rs.getString("actor"),
                        rs.getString("action"), rs.getString("detail")))
                .list();
    }

    /** Re-computes every hash from the genesis value and compares. */
    public Verification verify() {
        String prev = chain.genesis(CHAIN);
        if (prev == null) {
            return new Verification(true, 0, null);
        }
        var rows = jdbc.sql("SELECT seq, id, at, actor, action, detail, prev_hash, hash FROM audit_log ORDER BY seq")
                .query((rs, i) -> new Object[] {
                    rs.getLong("seq"), Db.uuid(rs, "id"), Db.instant(rs, "at"), rs.getString("actor"),
                    rs.getString("action"), rs.getString("detail"), rs.getString("prev_hash"), rs.getString("hash")})
                .list();
        long expectedSeq = 1;
        long checked = 0;
        for (Object[] r : rows) {
            long seq = (Long) r[0];
            String expected = hash(prev, (UUID) r[1], (Instant) r[2], (String) r[3], (String) r[4], (String) r[5]);
            if (seq != expectedSeq || !prev.equals(r[6]) || !expected.equals(r[7])) {
                return new Verification(false, checked, seq);
            }
            prev = expected;
            expectedSeq++;
            checked++;
        }
        if (!prev.equals(chain.head(CHAIN)) || chain.headSeq(CHAIN) != checked) {
            return new Verification(false, checked, checked + 1);
        }
        return new Verification(true, checked, null);
    }

    static String hash(String prev, UUID id, Instant at, String actor, String action, String detail) {
        return ChainService.hash(prev, id.toString(), Long.toString(at.toEpochMilli()), actor, action, detail);
    }

    private static String clip(String text, int max) {
        if (text == null) {
            return null;
        }
        String clean = text.replaceAll("\\p{Cntrl}", " ").strip();
        return clean.length() <= max ? clean : clean.substring(0, max);
    }
}
