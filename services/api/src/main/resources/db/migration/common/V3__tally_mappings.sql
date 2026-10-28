-- Which Tally Prime employee each worker is matched to (ADR-0015, design 16).
-- Names are the customer's own Tally master names, not worker personal data
-- beyond what the worker record already holds.
CREATE TABLE tally_mappings (
    worker_id  UUID PRIMARY KEY REFERENCES workers (id),
    tally_name VARCHAR(120) NOT NULL
);
