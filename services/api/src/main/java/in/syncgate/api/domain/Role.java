package in.syncgate.api.domain;

/**
 * Who is calling. OWNER, ADMIN and GATE_OPERATOR are people who unlocked
 * Admin mode with a PIN; DEVICE is the gate phone itself (device key);
 * SETUP is the unauthenticated first-run window before an owner exists.
 */
public enum Role {
    OWNER,
    ADMIN,
    GATE_OPERATOR,
    DEVICE,
    SETUP;

    /** True for the three roles that sign in with a PIN. */
    public boolean isUser() {
        return this == OWNER || this == ADMIN || this == GATE_OPERATOR;
    }
}
