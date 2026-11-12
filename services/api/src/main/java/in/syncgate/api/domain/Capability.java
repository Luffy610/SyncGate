package in.syncgate.api.domain;

import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

/**
 * What each caller may do (ADR-0004 section 2). The user rows mirror
 * {@code RoleCapabilities} in the Flutter {@code sg_domain} package, so the
 * server enforces the same rules the UI uses to hide buttons.
 */
public enum Capability {
    /** Read workers, shifts, today's events, settings. */
    READ_CORE,
    /** Mark attendance from the gate camera. */
    MARK_FACE,
    /** Guard fallback: pick a worker from the list. */
    MANUAL_ENTRY,
    /** Switch between gate/admin mode, save wizard progress. */
    SETTINGS_MODE,
    /** Change every setting. */
    SETTINGS_WRITE,
    ENROL_WORKERS,
    DELETE_WORKER,
    CORRECTIONS,
    REPORTS_AND_EXPORTS,
    BACKUP_RESTORE,
    LICENCE_AND_USERS,
    SHIFT_RULES,
    AUDIT_WRITE,
    AUDIT_READ,
    LICENCE_READ;

    private static final Set<Capability> GATE_BASIC = EnumSet.of(
            READ_CORE, MARK_FACE, MANUAL_ENTRY, SETTINGS_MODE, AUDIT_WRITE, LICENCE_READ);

    private static final Set<Capability> ADMIN = union(GATE_BASIC, EnumSet.of(
            SETTINGS_WRITE, ENROL_WORKERS, CORRECTIONS, REPORTS_AND_EXPORTS, SHIFT_RULES, AUDIT_READ));

    private static final Map<Role, Set<Capability>> GRANTS = Map.of(
            Role.DEVICE, GATE_BASIC,
            Role.GATE_OPERATOR, GATE_BASIC,
            Role.ADMIN, ADMIN,
            Role.OWNER, EnumSet.allOf(Capability.class),
            // First-run window, only while no owner exists.
            Role.SETUP, EnumSet.of(READ_CORE, SETTINGS_MODE, SETTINGS_WRITE, ENROL_WORKERS, SHIFT_RULES,
                    LICENCE_AND_USERS, AUDIT_WRITE, LICENCE_READ));

    public static boolean granted(Role role, Capability capability) {
        return GRANTS.getOrDefault(role, Set.of()).contains(capability);
    }

    private static Set<Capability> union(Set<Capability> a, Set<Capability> b) {
        EnumSet<Capability> out = EnumSet.copyOf(a);
        out.addAll(b);
        return out;
    }
}
