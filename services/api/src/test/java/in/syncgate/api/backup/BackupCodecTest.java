package in.syncgate.api.backup;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import in.syncgate.api.backup.BackupCodec.BackupException;
import in.syncgate.api.backup.BackupCodec.Kdf;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

class BackupCodecTest {

    private static final int MEM = 1024;
    private static final int ITER = 1;

    private byte[] seal(String text, String passphrase) {
        byte[] salt = BackupCodec.newSalt();
        byte[] key = BackupCodec.deriveKey(passphrase, salt, MEM, ITER);
        return BackupCodec.encrypt(text.getBytes(StandardCharsets.UTF_8), key, new Kdf(MEM, ITER, salt));
    }

    private byte[] open(byte[] file, String passphrase) {
        Kdf kdf = BackupCodec.readKdf(file);
        return BackupCodec.decrypt(file, BackupCodec.deriveKey(passphrase, kdf.salt(), kdf.memoryKib(), kdf.iterations()));
    }

    @Test
    void roundTripsIncludingHindiText() {
        String text = "{\"name\":\"रमेश कुमार\",\"n\":12345}";
        byte[] file = seal(text, "correct horse battery");
        assertEquals(text, new String(open(file, "correct horse battery"), StandardCharsets.UTF_8));
        assertEquals('S', file[0]);
        assertFalse(new String(file, StandardCharsets.ISO_8859_1).contains("रमेश"), "the body is encrypted");
    }

    @Test
    void sameDataEncryptsDifferentlyEveryTime() {
        byte[] a = seal("same", "passphrase-1");
        byte[] b = seal("same", "passphrase-1");
        assertNotEquals(Arrays.toString(a), Arrays.toString(b));
    }

    @Test
    void wrongPassphraseIsRejectedAsSuch() {
        byte[] file = seal("secret", "right passphrase");
        BackupException e = assertThrows(BackupException.class, () -> open(file, "wrong passphrase"));
        assertTrue(e.wrongPassphrase());
    }

    @Test
    void anyFlippedBitAnywhereIsDetected() {
        byte[] file = seal("secret data that matters", "pass-phrase-1");
        // Header bytes are authenticated as additional data; body bytes by the tag.
        for (int index : new int[] {10, 20, 30, BackupCodec.HEADER_SIZE - 1, BackupCodec.HEADER_SIZE, file.length / 2,
            file.length - 1}) {
            byte[] bad = file.clone();
            bad[index] ^= 0x01;
            assertThrows(BackupException.class, () -> open(bad, "pass-phrase-1"), "byte " + index);
        }
    }

    @Test
    void truncatedOrForeignFilesAreRejected() {
        byte[] file = seal("x", "pass-phrase-1");
        assertThrows(BackupException.class, () -> BackupCodec.readKdf(Arrays.copyOf(file, 10)));
        assertThrows(BackupException.class, () -> BackupCodec.readKdf("PK\u0003\u0004 this is a zip".getBytes()));
        assertThrows(BackupException.class, () -> open(Arrays.copyOf(file, file.length - 5), "pass-phrase-1"));
        assertThrows(BackupException.class, () -> BackupCodec.readKdf(null));
    }

    @Test
    void craftedHeaderCannotDemandHugeMemory() {
        byte[] file = seal("x", "pass-phrase-1");
        byte[] bad = file.clone();
        bad[5] = 0x7F; // memory field high byte: ~2 GiB
        assertThrows(BackupException.class, () -> BackupCodec.readKdf(bad));
    }

    @Test
    void keyDerivationIsDeterministicPerSaltAndDiffersAcrossSalts() {
        byte[] salt = BackupCodec.newSalt();
        assertArrayEquals(BackupCodec.deriveKey("p", salt, MEM, ITER), BackupCodec.deriveKey("p", salt, MEM, ITER));
        assertFalse(Arrays.equals(BackupCodec.deriveKey("p", salt, MEM, ITER),
                BackupCodec.deriveKey("p", BackupCodec.newSalt(), MEM, ITER)));
    }
}
