package in.syncgate.api.domain;

/** Small enums shared across features. Wire names follow {@link Wire}. */
public final class Enums {

    private Enums() {}

    public enum Direction { CHECK_IN, CHECK_OUT }

    public enum MarkMethod { FACE, MANUAL, CORRECTION }

    public enum FaceStatus { ENROLLED, NEEDS_FACE }

    public enum AppMode { SETUP, GATE, ADMIN }

    public enum ExceptionKind {
        MISSING_OUT, MANUAL, CLOCK, LOW_MARGIN, DUPLICATE, SPOOF_SUSPECT, LIVENESS_ACTIVE
    }

    public enum ManualReason { NOT_RECOGNISED, MASK_HELMET, INJURY, CAMERA_ISSUE, NEW_WORKER }

    public enum LicenceState { NONE, TRIAL, ACTIVE, GRACE_OVERDUE, RESTRICTED, REVOKED }

    public enum ExportFormat { EXCEL, CSV, TALLY }
}
