package in.syncgate.api.recognition;

import java.util.UUID;

/**
 * THE SEAM FOR FACE RECOGNITION.
 *
 * <p>Face detection, liveness, embedding and 1:N matching run on the phone, in
 * native code (ADR-0006/0007/0009), and templates never leave it. That code
 * lives in {@code packages/sg_vision} (Dart contract + Kotlin/Swift plugin)
 * and is written separately. What reaches this server is only the *outcome*
 * of a match: who, and the scores.
 *
 * <p>This port is where the server decides whether to trust that claim before
 * recording attendance. Today {@link MockFaceRecognition} accepts any
 * well-formed claim so the whole flow can be tested. When the real matcher
 * exists, replace the mock with an implementation that applies the calibrated
 * thresholds from the model card (T_match, margin, liveness) and set
 * {@code syncgate.recognition.mode=real}.
 */
public interface FaceRecognitionPort {

    /** What the device pipeline reported for one accepted frame sequence. */
    record MatchClaim(UUID workerId, double score, double margin, double liveness) {}

    /**
     * @param accepted  false means refuse to record the mark
     * @param lowMargin true if the mark is recorded but flagged for review
     * @param note      short reason, for the audit log
     */
    record Verdict(boolean accepted, boolean lowMargin, String note) {}

    Verdict verify(MatchClaim claim);
}
