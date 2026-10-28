-- SyncGate Phase 1 schema (ADR-0010, ADR-0011). One SQL set runs on PostgreSQL
-- and on H2 in PostgreSQL mode, so tests and production share migrations.

CREATE TABLE app_settings (
    id                    INT PRIMARY KEY CHECK (id = 1),
    mode                  VARCHAR(10) NOT NULL DEFAULT 'setup'
                              CHECK (mode IN ('setup', 'gate', 'admin')),
    setup_step            INT NOT NULL DEFAULT 1,
    language              VARCHAR(5) NOT NULL DEFAULT 'en',
    idle_minutes          INT NOT NULL DEFAULT 2 CHECK (idle_minutes BETWEEN 1 AND 10),
    cooldown_seconds      INT NOT NULL DEFAULT 120 CHECK (cooldown_seconds BETWEEN 60 AND 600),
    voice_volume          DOUBLE PRECISION NOT NULL DEFAULT 0.8,
    screen_fill_light     BOOLEAN NOT NULL DEFAULT TRUE,
    use_24_hour_clock     BOOLEAN NOT NULL DEFAULT FALSE,
    remind_backup_days    INT NOT NULL DEFAULT 7 CHECK (remind_backup_days BETWEEN 1 AND 60),
    auto_backup           BOOLEAN NOT NULL DEFAULT TRUE,
    gate_operator_id      VARCHAR(40) NOT NULL DEFAULT 'G-02',
    biometric_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    backup_passphrase_set BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at            TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE users (
    id              UUID PRIMARY KEY,
    name            VARCHAR(80) NOT NULL,
    role            VARCHAR(12) NOT NULL CHECK (role IN ('owner', 'admin', 'gateOperator')),
    pin_hash        VARCHAR(200),
    recovery_hash   VARCHAR(200),
    failed_attempts INT NOT NULL DEFAULT 0,
    locked_until    TIMESTAMP WITH TIME ZONE,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE UNIQUE INDEX ux_users_role ON users (role);

CREATE TABLE departments (
    name VARCHAR(80) PRIMARY KEY
);

CREATE TABLE shifts (
    id             UUID PRIMARY KEY,
    name           VARCHAR(60) NOT NULL,
    start_minute   INT NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
    end_minute     INT NOT NULL CHECK (end_minute BETWEEN 0 AND 1439),
    grace_minutes  INT NOT NULL DEFAULT 10 CHECK (grace_minutes BETWEEN 0 AND 120),
    weekly_off     INT NOT NULL DEFAULT 7 CHECK (weekly_off BETWEEN 1 AND 7),
    updated_at     TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE workers (
    id            UUID PRIMARY KEY,
    code          VARCHAR(20) NOT NULL,
    name          VARCHAR(120) NOT NULL,
    date_of_birth DATE NOT NULL,
    department    VARCHAR(80) NOT NULL,
    designation   VARCHAR(80) NOT NULL,
    shift_id      UUID NOT NULL REFERENCES shifts (id),
    contractor    VARCHAR(120),
    phone         VARCHAR(20),
    language      VARCHAR(5) NOT NULL DEFAULT 'hi',
    face_status   VARCHAR(12) NOT NULL DEFAULT 'needsFace'
                      CHECK (face_status IN ('enrolled', 'needsFace')),
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    on_leave      BOOLEAN NOT NULL DEFAULT FALSE,
    erased        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE UNIQUE INDEX ux_workers_code ON workers (code);

-- Consents are append-only: withdrawal is a new row, never an edit.
CREATE TABLE consents (
    id             UUID PRIMARY KEY,
    worker_id      UUID NOT NULL REFERENCES workers (id),
    notice_version VARCHAR(40) NOT NULL,
    language       VARCHAR(5) NOT NULL,
    admin_id       VARCHAR(80) NOT NULL,
    accepted_at    TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX ix_consents_worker ON consents (worker_id);

-- Hash chains (ADR-0011). The head row doubles as the lock that serialises
-- appends, so a chain can never fork.
CREATE TABLE chain_heads (
    name      VARCHAR(20) PRIMARY KEY,
    genesis   VARCHAR(64) NOT NULL,
    last_seq  BIGINT NOT NULL,
    last_hash VARCHAR(64) NOT NULL
);

-- Attendance events are facts: append-only. Corrections are new rows.
CREATE TABLE attendance_events (
    seq          BIGINT NOT NULL,
    id           UUID PRIMARY KEY,
    worker_id    UUID NOT NULL REFERENCES workers (id),
    at           TIMESTAMP WITH TIME ZONE NOT NULL,
    direction    VARCHAR(10) NOT NULL CHECK (direction IN ('checkIn', 'checkOut')),
    method       VARCHAR(12) NOT NULL CHECK (method IN ('face', 'manual', 'correction')),
    reason       VARCHAR(200),
    marked_by    VARCHAR(80),
    on_time      BOOLEAN NOT NULL,
    match_score  DOUBLE PRECISION,
    match_margin DOUBLE PRECISION,
    liveness     DOUBLE PRECISION,
    prev_hash    VARCHAR(64) NOT NULL,
    hash         VARCHAR(64) NOT NULL
);
CREATE UNIQUE INDEX ux_events_seq ON attendance_events (seq);
CREATE INDEX ix_events_worker_at ON attendance_events (worker_id, at);
CREATE INDEX ix_events_at ON attendance_events (at);

CREATE TABLE exceptions (
    id          UUID PRIMARY KEY,
    kind        VARCHAR(20) NOT NULL,
    at          TIMESTAMP WITH TIME ZONE NOT NULL,
    worker_id   UUID REFERENCES workers (id),
    resolved    BOOLEAN NOT NULL DEFAULT FALSE,
    event_id    UUID,
    actor       VARCHAR(80),
    reason      VARCHAR(20),
    in_at       TIMESTAMP WITH TIME ZONE,
    minutes     INT,
    event_count INT
);
CREATE INDEX ix_exceptions_open ON exceptions (resolved, at);

CREATE TABLE audit_log (
    seq       BIGINT NOT NULL,
    id        UUID PRIMARY KEY,
    at        TIMESTAMP WITH TIME ZONE NOT NULL,
    actor     VARCHAR(80) NOT NULL,
    action    VARCHAR(80) NOT NULL,
    detail    VARCHAR(500),
    prev_hash VARCHAR(64) NOT NULL,
    hash      VARCHAR(64) NOT NULL
);
CREATE UNIQUE INDEX ux_audit_seq ON audit_log (seq);

CREATE TABLE licence (
    id            INT PRIMARY KEY CHECK (id = 1),
    state         VARCHAR(14) NOT NULL DEFAULT 'none',
    licence_key   VARCHAR(30),
    expires_on    DATE,
    trial_started DATE,
    last_checkin  TIMESTAMP WITH TIME ZONE,
    token         TEXT
);

CREATE TABLE issued_licence_keys (
    licence_key  VARCHAR(30) PRIMARY KEY,
    max_workers  INT NOT NULL DEFAULT 25,
    revoked      BOOLEAN NOT NULL DEFAULT FALSE,
    activated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE backups (
    id          UUID PRIMARY KEY,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    destination VARCHAR(40) NOT NULL,
    file_name   VARCHAR(120) NOT NULL,
    sha256      VARCHAR(64) NOT NULL,
    size_bytes  BIGINT NOT NULL,
    created_by  VARCHAR(80) NOT NULL
);

CREATE TABLE backup_key (
    id       INT PRIMARY KEY CHECK (id = 1),
    salt     VARCHAR(64) NOT NULL,
    wrapped  TEXT NOT NULL,
    verifier VARCHAR(64) NOT NULL
);

CREATE TABLE exports (
    id         UUID PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    format     VARCHAR(8) NOT NULL,
    period     VARCHAR(7) NOT NULL,
    sha256     VARCHAR(64) NOT NULL,
    row_count  INT NOT NULL,
    created_by VARCHAR(80) NOT NULL
);
