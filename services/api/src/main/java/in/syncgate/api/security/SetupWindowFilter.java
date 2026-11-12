package in.syncgate.api.security;

import in.syncgate.api.user.UserService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * While no owner exists the setup wizard has to call the API before it has
 * any credentials. In that window (and only then) a request with no token is
 * given the narrow SETUP capability set. Once the owner is created the window
 * closes for good and every call needs a token.
 */
@Component
public class SetupWindowFilter extends OncePerRequestFilter {

    private final UserService users;

    public SetupWindowFilter(UserService users) {
        this.users = users;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        boolean anonymous = request.getHeader(HttpHeaders.AUTHORIZATION) == null
                && SecurityContextHolder.getContext().getAuthentication() == null;
        if (anonymous && request.getRequestURI().startsWith("/api/") && !users.ownerExists()) {
            SecurityContextHolder.getContext().setAuthentication(new SetupAuthentication());
        }
        chain.doFilter(request, response);
    }
}
