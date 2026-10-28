package in.syncgate.api.common;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.HexFormat;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Tamper-evident hash chains (ADR-0011 section 3). Each row stores
 * {@code hash = SHA-256(prev_hash, fields...)}, so editing or deleting a row
 * breaks every hash after it. The chain's head row is locked with
 * {@code SELECT ... FOR UPDATE} while appending, which serialises writers and
 * means two requests can never extend the same predecessor.
 */
@Component
public class ChainService {

    public record Link(long seq, String prevHash) {}

    private final JdbcClient jdbc;
    private final SecureRandom random = new SecureRandom();

    public ChainService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Locks the chain head and returns the next sequence number. */
    @Transactional(propagation = Propagation.MANDATORY)
    public Link reserve(String chain) {
        var head = jdbc.sql("SELECT genesis, last_seq, last_hash FROM chain_heads WHERE name = :n FOR UPDATE")
                .param("n", chain)
                .query((rs, i) -> new String[] {rs.getString(1), String.valueOf(rs.getLong(2)), rs.getString(3)})
                .optional();
        if (head.isEmpty()) {
            String genesis = randomHex();
            jdbc.sql("INSERT INTO chain_heads (name, genesis, last_seq, last_hash) VALUES (:n, :g, 0, :g)")
                    .param("n", chain)
                    .param("g", genesis)
                    .update();
            return new Link(1, genesis);
        }
        return new Link(Long.parseLong(head.get()[1]) + 1, head.get()[2]);
    }

    /** Records the new head after the row has been inserted. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void commit(String chain, long seq, String hash) {
        jdbc.sql("UPDATE chain_heads SET last_seq = :s, last_hash = :h WHERE name = :n")
                .param("s", seq)
                .param("h", hash)
                .param("n", chain)
                .update();
    }

    public String genesis(String chain) {
        return jdbc.sql("SELECT genesis FROM chain_heads WHERE name = :n")
                .param("n", chain)
                .query(String.class)
                .optional()
                .orElse(null);
    }

    public String head(String chain) {
        return jdbc.sql("SELECT last_hash FROM chain_heads WHERE name = :n")
                .param("n", chain)
                .query(String.class)
                .optional()
                .orElse(null);
    }

    public long headSeq(String chain) {
        return jdbc.sql("SELECT last_seq FROM chain_heads WHERE name = :n")
                .param("n", chain)
                .query(Long.class)
                .optional()
                .orElse(0L);
    }

    /** Length-prefixed fields so ("ab","c") and ("a","bc") hash differently. */
    public static String hash(String prev, String... fields) {
        try {
            MessageDigest sha = MessageDigest.getInstance("SHA-256");
            sha.update(prev.getBytes(StandardCharsets.UTF_8));
            for (String field : fields) {
                byte[] bytes = (field == null ? "\u0000null" : field).getBytes(StandardCharsets.UTF_8);
                sha.update((byte) 0x1F);
                sha.update(Integer.toString(bytes.length).getBytes(StandardCharsets.UTF_8));
                sha.update((byte) ':');
                sha.update(bytes);
            }
            return HexFormat.of().formatHex(sha.digest());
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private String randomHex() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }
}
