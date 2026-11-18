-- PostgreSQL schema for the Expense Tracker backend.
-- Usage: psql "$DATABASE_URL" -f schema.sql

CREATE TABLE IF NOT EXISTS expenses (
    id          BIGSERIAL PRIMARY KEY,
    amount      NUMERIC NOT NULL,
    category    VARCHAR NOT NULL,
    description TEXT,
    date        DATE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
