package in.syncgate.api.security;

import java.util.List;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

/**
 * Anonymous caller during first-run setup, when no owner exists yet. It is
 * granted only the narrow {@code SETUP} capability set and vanishes the moment
 * the owner is created.
 */
public final class SetupAuthentication extends AbstractAuthenticationToken {

    public SetupAuthentication() {
        super(List.of(new SimpleGrantedAuthority("ROLE_SETUP")));
        setAuthenticated(true);
    }

    @Override
    public Object getCredentials() {
        return "";
    }

    @Override
    public Object getPrincipal() {
        return "setup";
    }
}
