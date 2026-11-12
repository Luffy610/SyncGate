package in.syncgate.api.security;

import in.syncgate.api.domain.Capability;
import in.syncgate.api.domain.Role;
import in.syncgate.api.domain.Wire;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/** The authenticated caller of the current request. */
public record Caller(Role role, String subject, String label) {

    public static Caller current() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth instanceof SetupAuthentication) {
            return new Caller(Role.SETUP, "setup", "Setup");
        }
        if (auth instanceof JwtAuthenticationToken jwt) {
            String role = jwt.getToken().getClaimAsString("role");
            for (Role candidate : Role.values()) {
                if (Wire.of(candidate).equals(role)) {
                    String name = jwt.getToken().getClaimAsString("name");
                    return new Caller(candidate, jwt.getToken().getSubject(), name == null ? role : name);
                }
            }
        }
        return null;
    }

    public static Caller require() {
        Caller caller = current();
        if (caller == null) {
            throw new org.springframework.security.access.AccessDeniedException("not signed in");
        }
        return caller;
    }

    /** Used by {@code @PreAuthorize("@caps.can('ENROL_WORKERS')")}. */
    @Component("caps")
    public static class Caps {
        public boolean can(String capability) {
            Caller caller = current();
            return caller != null && Capability.granted(caller.role(), Capability.valueOf(capability));
        }
    }
}
