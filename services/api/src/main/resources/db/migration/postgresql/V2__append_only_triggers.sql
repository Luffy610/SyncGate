-- Production hardening (ADR-0011 section 3): the database itself refuses to
-- change or delete facts. On H2 (dev and tests) the repositories simply never
-- issue such statements and the integrity check detects tampering.
-- Backup restore runs as a migration-style bulk load with the triggers off
-- (see RestoreService), inside one transaction.
CREATE FUNCTION sg_reject_change() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'table % is append-only', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_append_only
    BEFORE UPDATE OR DELETE ON attendance_events
    FOR EACH ROW EXECUTE FUNCTION sg_reject_change();

CREATE TRIGGER trg_audit_append_only
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION sg_reject_change();

CREATE TRIGGER trg_consents_append_only
    BEFORE UPDATE OR DELETE ON consents
    FOR EACH ROW EXECUTE FUNCTION sg_reject_change();
