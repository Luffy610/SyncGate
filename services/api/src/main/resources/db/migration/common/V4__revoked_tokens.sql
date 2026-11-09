-- Access tokens that were ended early (admin returned to the gate / signed
-- out). Rows are only needed until the token would have expired anyway.
CREATE TABLE revoked_tokens (
    jti        VARCHAR(64) PRIMARY KEY,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX ix_revoked_expires ON revoked_tokens (expires_at);
