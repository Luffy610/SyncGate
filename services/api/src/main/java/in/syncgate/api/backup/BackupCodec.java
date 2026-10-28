package in.syncgate.api.backup;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.bouncycastle.crypto.generators.Argon2BytesGenerator;
import org.bouncycastle.crypto.params.Argon2Parameters;

/**
 * The {@code .sgbackup} file format (ADR-0013).
 *
 * <pre>
 * header (39 bytes, plaintext, also the GCM additional data):
 *   "SGBK" | version u8 | argon2 memory KiB u32 | iterations u8 | parallelism u8 | salt[16] | nonce[12]
 * body: AES-256-GCM( gzip( JSON ) )
 * </pre>
 *
 * The key is {@code Argon2id(passphrase, salt)}. The vendor never sees the
 * passphrase, so a backup cannot be opened without it. Tampering with any
 * header byte or the body fails the GCM tag check.
 */
public final class BackupCodec {

    public static final int VERSION = 1;
    public static final int HEADER_SIZE = 4 + 1 + 4 + 1 + 1 + 16 + 12;
    private static final byte[] MAGIC = "SGBK".getBytes(StandardCharsets.US_ASCII);
    private static final int MAX_PLAINTEXT = 200 * 1024 * 1024;
    private static final SecureRandom RANDOM = new SecureRandom();

    /** Wrong passphrase, damaged file, or not a SyncGate backup. */
    public static class BackupException extends RuntimeException {
        private final boolean wrongPassphrase;

        public BackupException(String message, boolean wrongPassphrase) {
            super(message, null, false, false);
            this.wrongPassphrase = wrongPassphrase;
        }

        public boolean wrongPassphrase() {
            return wrongPassphrase;
        }
    }

    /** Key-derivation settings carried in the header. */
    public record Kdf(int memoryKib, int iterations, byte[] salt) {}

    private BackupCodec() {}

    public static byte[] newSalt() {
        byte[] salt = new byte[16];
        RANDOM.nextBytes(salt);
        return salt;
    }

    public static byte[] deriveKey(String passphrase, byte[] salt, int memoryKib, int iterations) {
        Argon2Parameters params = new Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
                .withVersion(Argon2Parameters.ARGON2_VERSION_13)
                .withIterations(iterations).withMemoryAsKB(memoryKib).withParallelism(1).withSalt(salt).build();
        Argon2BytesGenerator generator = new Argon2BytesGenerator();
        generator.init(params);
        byte[] key = new byte[32];
        generator.generateBytes(passphrase.getBytes(StandardCharsets.UTF_8), key);
        return key;
    }

    public static byte[] encrypt(byte[] json, byte[] key, Kdf kdf) {
        try {
            byte[] nonce = new byte[12];
            RANDOM.nextBytes(nonce);
            byte[] header = header(kdf, nonce);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
            cipher.updateAAD(header);
            byte[] body = cipher.doFinal(gzip(json));
            ByteArrayOutputStream out = new ByteArrayOutputStream(header.length + body.length);
            out.write(header);
            out.write(body);
            return out.toByteArray();
        } catch (GeneralSecurityException | IOException e) {
            throw new IllegalStateException("backup encryption failed", e);
        }
    }

    /** Reads the key-derivation settings so the caller can derive the key from a passphrase. */
    public static Kdf readKdf(byte[] file) {
        if (file == null || file.length < HEADER_SIZE + 16) {
            throw new BackupException("This is not a SyncGate backup", false);
        }
        ByteBuffer buf = ByteBuffer.wrap(file);
        byte[] magic = new byte[4];
        buf.get(magic);
        if (!Arrays.equals(magic, MAGIC)) {
            throw new BackupException("This is not a SyncGate backup", false);
        }
        int version = buf.get() & 0xFF;
        if (version != VERSION) {
            throw new BackupException("This backup was made by a newer version of SyncGate", false);
        }
        int memory = buf.getInt();
        int iterations = buf.get() & 0xFF;
        int parallelism = buf.get() & 0xFF;
        // Bounds stop a crafted header from asking for gigabytes of memory.
        if (memory < 1024 || memory > 262_144 || iterations < 1 || iterations > 10 || parallelism != 1) {
            throw new BackupException("The backup file is damaged", false);
        }
        byte[] salt = new byte[16];
        buf.get(salt);
        return new Kdf(memory, iterations, salt);
    }

    public static byte[] decrypt(byte[] file, byte[] key) {
        readKdf(file);
        try {
            byte[] header = Arrays.copyOfRange(file, 0, HEADER_SIZE);
            byte[] nonce = Arrays.copyOfRange(file, HEADER_SIZE - 12, HEADER_SIZE);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
            cipher.updateAAD(header);
            byte[] compressed = cipher.doFinal(file, HEADER_SIZE, file.length - HEADER_SIZE);
            return gunzip(compressed);
        } catch (javax.crypto.AEADBadTagException e) {
            // Wrong passphrase and a damaged file look the same to GCM.
            throw new BackupException("Wrong passphrase, or the backup file is damaged", true);
        } catch (GeneralSecurityException | IOException e) {
            throw new BackupException("The backup file is damaged", false);
        }
    }

    private static byte[] header(Kdf kdf, byte[] nonce) {
        ByteBuffer buf = ByteBuffer.allocate(HEADER_SIZE);
        buf.put(MAGIC).put((byte) VERSION).putInt(kdf.memoryKib()).put((byte) kdf.iterations()).put((byte) 1)
                .put(kdf.salt()).put(nonce);
        return buf.array();
    }

    private static byte[] gzip(byte[] data) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (GZIPOutputStream gz = new GZIPOutputStream(out)) {
            gz.write(data);
        }
        return out.toByteArray();
    }

    private static byte[] gunzip(byte[] data) throws IOException {
        try (GZIPInputStream gz = new GZIPInputStream(new ByteArrayInputStream(data));
                ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] chunk = new byte[16 * 1024];
            int read;
            while ((read = gz.read(chunk)) > 0) {
                out.write(chunk, 0, read);
                if (out.size() > MAX_PLAINTEXT) {
                    throw new IOException("backup is too large to restore");
                }
            }
            return out.toByteArray();
        }
    }
}
