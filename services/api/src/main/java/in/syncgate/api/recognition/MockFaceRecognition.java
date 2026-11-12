package in.syncgate.api.recognition;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Mock verdicts for development and tests. It only checks the numbers are in
 * range and flags a thin margin; it does NOT judge whether a face matches.
 * Not for production use: {@code StartupGuard} cannot know, so the real
 * implementation must replace this bean (mode {@code real}).
 */
@Component
@ConditionalOnProperty(name = "syncgate.recognition.mode", havingValue = "mock", matchIfMissing = true)
public class MockFaceRecognition implements FaceRecognitionPort {

    /** ADR-0009 starting margin. */
    static final double MARGIN_FLOOR = 0.08;

    @Override
    public Verdict verify(MatchClaim claim) {
        boolean inRange = in01(claim.score()) && in01(claim.liveness()) && claim.margin() >= 0 && claim.margin() <= 1;
        if (!inRange) {
            return new Verdict(false, false, "scores out of range");
        }
        boolean thin = claim.margin() < MARGIN_FLOOR;
        return new Verdict(true, thin, thin ? "low margin" : "ok");
    }

    private static boolean in01(double value) {
        return value >= 0 && value <= 1 && !Double.isNaN(value);
    }
}
