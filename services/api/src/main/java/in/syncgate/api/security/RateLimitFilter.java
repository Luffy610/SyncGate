package in.syncgate.api.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Sliding-window limiter for the sign-in style endpoints, per client address.
 * It is a second line of defence behind the per-account PIN lockout, and it
 * also stops cheap request floods against the Argon2 hashing.
 */
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    static final int LIMIT = 30;
    static final Duration WINDOW = Duration.ofMinutes(1);

    private final ConcurrentHashMap<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String uri = request.getRequestURI();
        return !(uri.startsWith("/api/v1/auth/") || uri.equals("/api/v1/licence/activate")
                || uri.equals("/api/v1/backups/restore"));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        long now = System.currentTimeMillis();
        Deque<Long> window = hits.computeIfAbsent(request.getRemoteAddr(), k -> new ArrayDeque<>());
        boolean limited;
        synchronized (window) {
            while (!window.isEmpty() && now - window.peekFirst() > WINDOW.toMillis()) {
                window.pollFirst();
            }
            limited = window.size() >= LIMIT;
            if (!limited) {
                window.addLast(now);
            }
        }
        if (hits.size() > 10_000) {
            hits.entrySet().removeIf(e -> e.getValue().isEmpty());
        }
        if (limited) {
            response.setStatus(429);
            response.setHeader("Retry-After", "60");
            response.setContentType("application/json");
            response.getWriter().write("{\"code\":\"RATE_LIMITED\",\"message\":\"Too many requests\",\"details\":{}}");
            return;
        }
        chain.doFilter(request, response);
    }
}
