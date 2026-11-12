package in.syncgate.api.security;

import in.syncgate.api.config.SyncgateProperties;
import java.io.IOException;
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Stateless bearer-token security. No sessions or cookies, so CSRF does not
 * apply; every route except the sign-in family needs a valid token, and
 * everything not under /api is denied.
 */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, JwtService jwt, SetupWindowFilter setupWindow,
            RateLimitFilter rateLimit, SyncgateProperties props) throws Exception {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(token ->
                List.of(new SimpleGrantedAuthority("ROLE_" + token.getClaimAsString("role"))));

        http.csrf(csrf -> csrf.disable())
                .cors(cors -> cors.configurationSource(corsSource(props)))
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .headers(h -> h
                        .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'none'; frame-ancestors 'none'"))
                        .frameOptions(f -> f.deny())
                        .referrerPolicy(r -> r.policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.NO_REFERRER))
                        .httpStrictTransportSecurity(hsts -> hsts.includeSubDomains(true).maxAgeInSeconds(31_536_000))
                        .cacheControl(Customizer.withDefaults()))
                .authorizeHttpRequests(a -> a
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/setup/status").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/v1/auth/login", "/api/v1/auth/device",
                                "/api/v1/auth/owner", "/api/v1/auth/reset-owner-pin").permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().denyAll())
                .oauth2ResourceServer(o -> o
                        .jwt(j -> j.decoder(jwt.decoder()).jwtAuthenticationConverter(converter))
                        .authenticationEntryPoint((req, res, ex) -> writeError(res, 401, "UNAUTHENTICATED",
                                "Please sign in again"))
                        .accessDeniedHandler((req, res, ex) -> writeError(res, 403, "NOT_ALLOWED",
                                "You are not allowed to do that")))
                .exceptionHandling(e -> e
                        .authenticationEntryPoint((req, res, ex) -> writeError(res, 401, "UNAUTHENTICATED",
                                "Please sign in again"))
                        .accessDeniedHandler((req, res, ex) -> writeError(res, 403, "NOT_ALLOWED",
                                "You are not allowed to do that")))
                .addFilterAfter(setupWindow, BearerTokenAuthenticationFilter.class)
                .addFilterBefore(rateLimit, BearerTokenAuthenticationFilter.class);
        return http.build();
    }

    /** The two custom filters run inside the security chain only, not twice. */
    @Bean
    org.springframework.boot.web.servlet.FilterRegistrationBean<SetupWindowFilter> setupWindowRegistration(
            SetupWindowFilter filter) {
        var registration = new org.springframework.boot.web.servlet.FilterRegistrationBean<>(filter);
        registration.setEnabled(false);
        return registration;
    }

    @Bean
    org.springframework.boot.web.servlet.FilterRegistrationBean<RateLimitFilter> rateLimitRegistration(
            RateLimitFilter filter) {
        var registration = new org.springframework.boot.web.servlet.FilterRegistrationBean<>(filter);
        registration.setEnabled(false);
        return registration;
    }

    /** Argon2id for PINs and the recovery code (ADR-0004). */
    @Bean
    PasswordEncoder pinEncoder(SyncgateProperties props) {
        var sec = props.security();
        return new Argon2PasswordEncoder(16, 32, 1, sec.argon2MemoryKib(), sec.argon2Iterations());
    }

    private static CorsConfigurationSource corsSource(SyncgateProperties props) {
        CorsConfiguration cors = new CorsConfiguration();
        List<String> origins = props.security().allowedOrigins().stream().filter(o -> !o.isBlank()).toList();
        // An empty list means no browser origin is allowed: the mobile app is
        // not a browser and does not need CORS.
        cors.setAllowedOrigins(origins);
        cors.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        cors.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        cors.setExposedHeaders(List.of("X-Row-Count", "Content-Disposition", "X-Content-Sha256"));
        cors.setMaxAge(600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", cors);
        return source;
    }

    private static void writeError(jakarta.servlet.http.HttpServletResponse res, int status, String code,
            String message) throws IOException {
        res.setStatus(status);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.getWriter().write("{\"code\":\"" + code + "\",\"message\":\"" + message + "\",\"details\":{}}");
    }
}
