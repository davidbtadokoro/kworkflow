PRAGMA foreign_keys = 1;
BEGIN TRANSACTION;
-- Tables

-- This table holds the metadata of the config files handled by kw
CREATE TABLE IF NOT EXISTS "kernel_config" (
  "id" INTEGER NOT NULL UNIQUE,
  "name" TEXT NOT NULL UNIQUE,
  "description" TEXT,
  "path" TEXT NOT NULL UNIQUE,
  "last_updated_datetime" TEXT NOT NULL,
  PRIMARY KEY("id")
);

-- This table holds the names of the commands that kw keeps track of, like
-- build and deploy
CREATE TABLE IF NOT EXISTS "command_label" (
  "id" INTEGER NOT NULL UNIQUE,
  "name" TEXT NOT NULL UNIQUE,
  PRIMARY KEY("id")
);

-- Table containing the possible exit status of an executed commmand
CREATE TABLE IF NOT EXISTS "status" (
  "id" INTEGER NOT NULL UNIQUE,
  "name" TEXT NOT NULL UNIQUE,
  PRIMARY KEY("id")
);

-- Table containing user created tags
CREATE TABLE IF NOT EXISTS "tag" (
  "id" INTEGER NOT NULL UNIQUE,
  "name" TEXT NOT NULL UNIQUE,
  -- The 'active' attribute is a boolean to denote if the tag is active
  -- or not. This is useful for listing just a subset of tags in the DB
  "active" INTEGER NOT NULL CHECK ("active" IN (0, 1)) DEFAULT 1,
  PRIMARY KEY("id")
);

-- This is the table that holds the events triggered by kw, currently pertains
-- to the executed commands that are saved and the pomodoro sessions created
CREATE TABLE IF NOT EXISTS "event" (
  "id" INTEGER NOT NULL UNIQUE,
  "date" TEXT NOT NULL,
  "time" TEXT,
  PRIMARY KEY("id")
);

-- This is the table that holds the events triggered by kw, currently pertains
-- to the executed commands that are saved and the pomodoro sessions created
CREATE TABLE IF NOT EXISTS "patch" (
  "id" INTEGER,
  "created_at" TEXT DEFAULT (datetime('now','localtime')),
  "status" VARCHAR(50) DEFAULT ('SENT') NOT NULL,
  "title" TEXT NOT NULL, 
  "last_patch_id" INTEGER,
  "outdated" INTEGER NOT NULL CHECK ("outdated" IN (0, 1)) DEFAULT 0,
  "version" INTEGER NOT NULL,
  "author" TEXT,
  "contribution_id" INTEGER NOT NULL,
  "commit_hash" TEXT,
  CHECK ("status" IN ('SENT', 'APPROVED', 'MERGED', 'REVIEWED', 'REJECTED')),
  PRIMARY KEY("id"),
  FOREIGN KEY ("last_patch_id") REFERENCES "patch"("id") ON DELETE CASCADE,
  FOREIGN KEY ("contribution_id") REFERENCES "contribution"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "patch_tag" (
  "id" INTEGER,
  "name" VARCHAR(50) NOT NULL UNIQUE,
  PRIMARY KEY("id")
);

CREATE TABLE IF NOT EXISTS "patch_tag_relation" (
  "id" INTEGER,
  "tag_id" INTEGER NOT NULL,
  "patch_id" INTEGER NOT NULL,
  PRIMARY KEY("id"),
  FOREIGN KEY ("tag_id") REFERENCES "patch_tag"("id") ON DELETE CASCADE,
  FOREIGN KEY ("patch_id") REFERENCES "patch"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "submission" (
  "id" INTEGER,
  "created_at" TEXT DEFAULT (datetime('now','localtime')),
  "contribution_id" INTEGER NOT NULL,
  "send_by" TEXT NOT NULL,
  PRIMARY KEY("id"),
  FOREIGN KEY ("contribution_id") REFERENCES "contribution"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "patch_submission" (
  "patch_id" INTEGER NOT NULL,
  "submission_id" INTEGER NOT NULL,
  "message_id" TEXT NOT NULL,
  PRIMARY KEY ("patch_id", "submission_id", "message_id"),
  FOREIGN KEY ("submission_id") REFERENCES "submission"("id") ON DELETE CASCADE,
  FOREIGN KEY ("patch_id") REFERENCES "patch"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "contribution" (
  "id" INTEGER,
  "created_at" TEXT DEFAULT (datetime('now','localtime')),
  "status" VARCHAR(50) DEFAULT ('SENT') NOT NULL,
  "title" TEXT NOT NULL UNIQUE,
  "last_interaction_at" TEXT DEFAULT (datetime('now','localtime')),
  "active" INTEGER NOT NULL CHECK ("active" IN (0, 1)) DEFAULT 1,
  "author_email" TEXT NOT NULL,
  "repository_id" INTEGER,
  PRIMARY KEY("id"),
  FOREIGN KEY ("repository_id") REFERENCES "repository"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "repository" (
  "id" INTEGER,
  "created_at" TEXT DEFAULT (datetime('now','localtime')),
  "name" TEXT NOT NULL,
  "origin_url" TEXT NOT NULL,
  "branch_name" TEXT NOT NULL,
  PRIMARY KEY("id")
  UNIQUE("origin_url", "branch_name")
);

CREATE TABLE IF NOT EXISTS "repository_maintainer" (
  "id" INTEGER,
  "repository_id" INTEGER NOT NULL,
  "contact_id" INTEGER NOT NULL,
  PRIMARY KEY ("repository_id", "contact_id"),
  FOREIGN KEY ("repository_id") REFERENCES "repository"("id") ON DELETE CASCADE
);

-- This is the relationship between an "event" that executes a given
-- "command_label"
CREATE TABLE IF NOT EXISTS "executed" (
  "id" INTEGER NOT NULL UNIQUE,
  "command_label_id" INTEGER NOT NULL,
  "elapsed_time_in_secs" INTEGER NOT NULL,
  "status_id" INTEGER NOT NULL,
  PRIMARY KEY("id"),
  FOREIGN KEY("id") REFERENCES "event"("id")
    ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY("command_label_id") REFERENCES "command_label"("id")
    ON UPDATE CASCADE ON DELETE RESTRICT,
  FOREIGN KEY("status_id") REFERENCES "status"("id")
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Table containing the information related to each pomodoro timebox
CREATE TABLE IF NOT EXISTS "timebox" (
  "id" INTEGER NOT NULL UNIQUE,
  "duration" INTEGER NOT NULL,
  "description" TEXT,
  "tag_id" INTEGER NOT NULL,
  PRIMARY KEY("id"),
  FOREIGN KEY("id") REFERENCES "event"("id")
    ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY("tag_id") REFERENCES "tag"("id")
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Populate commands and status tables
INSERT OR IGNORE INTO "status" ("name") VALUES
  ('success'),
  ('failure'),
  ('interrupted'),
  ('unknown');

INSERT OR IGNORE INTO "command_label" ("name") VALUES
  ('backup'),
  ('bd'),
  ('build'),
  ('clear-cache'),
  ('codestyle'),
  ('config'),
  ('debug'),
  ('deploy'),
  ('device'),
  ('diff'),
  ('drm'),
  ('env'),
  ('explore'),
  ('init'),
  ('kernel_config_manager'),
  ('list'),
  ('mail'),
  ('maintainers'),
  ('man'),
  ('modules_deploy'),
  ('pomodoro'),
  ('remote'),
  ('report'),
  ('self-update'),
  ('ssh'),
  ('uninstall'),
  ('vm');

-- Views
-- This view shows the currently active pomodoro sessions
CREATE VIEW IF NOT EXISTS "active_timebox"
AS
SELECT
  "e_id" AS "id",
  "tag",
  "date",
  "time",
  "duration",
  "description"
FROM
  (SELECT "id" AS "e_id", "date", "time" FROM "event" ORDER BY "date")
JOIN "timebox" ON "e_id" IS "timebox"."id"
JOIN (SELECT "id" AS "g_id", "name" AS "tag" FROM "tag") ON "g_id" IS "timebox"."tag_id"
WHERE
  CAST (strftime('%s',"date"||'T'||"time",'utc') + "duration" AS INTEGER) >= CAST (strftime('%s','now') AS INTEGER);

-- This view aggregates all the pomodoro sessions on record
CREATE VIEW IF NOT EXISTS "pomodoro_report"
AS
SELECT
  "e_id" AS "id",
  "tag_id",
  "name" AS "tag_name",
  "date",
  "time",
  "duration",
  "description"
FROM
  (SELECT "id" AS "e_id", "date", "time" FROM "event")
JOIN "timebox" ON "timebox"."id" IS "e_id"
JOIN "tag" ON "tag"."id" IS "timebox"."tag_id";

-- This view aggregates all data relevant to the statistics reports
CREATE VIEW IF NOT EXISTS "statistics_report"
AS
SELECT
  "e_id" AS "id",
  "name" AS "label_name",
  "status_name" AS "status",
  "date",
  "time",
  "elapsed_time_in_secs"
FROM
  (SELECT "id" AS "e_id", "date", "time" FROM "event")
JOIN "executed" ON "executed"."id" IS "e_id"
JOIN "command_label" ON "command_label"."id" IS "executed"."command_label_id"
JOIN (SELECT "id" AS "s_id", "name" AS "status_name" FROM "status") ON "s_id" IS "executed"."status_id";

-- Indexes
CREATE INDEX IF NOT EXISTS "command_label_idx" ON "command_label" (
  "name" ASC,
  "id"
);

CREATE INDEX IF NOT EXISTS "tag_idx" ON "tag" (
  "active" DESC,
  "name" ASC,
  "id"
);

CREATE INDEX IF NOT EXISTS "chronological_events" ON "event" (
  "date" ASC,
  "time" ASC,
  "id"
);

CREATE INDEX IF NOT EXISTS "executed_idx" ON "executed" (
  "command_label_id" ASC,
  "status_id" ASC,
  "elapsed_time_in_secs" DESC,
  "id"
);

CREATE INDEX IF NOT EXISTS "timebox_idx" ON "timebox" (
  "tag_id" ASC,
  "duration" DESC,
  "id",
  "description"
);

-- Triggers
CREATE TRIGGER IF NOT EXISTS "delete_pomodoro" INSTEAD OF DELETE ON "pomodoro_report"
  BEGIN
    DELETE FROM "timebox" WHERE "timebox"."id" IS "OLD"."id";
    DELETE FROM "event" WHERE "event"."id" IS "OLD"."id";
  END;

CREATE TRIGGER IF NOT EXISTS "delete_statistics" INSTEAD OF DELETE ON "statistics_report"
  BEGIN
    DELETE FROM "executed" WHERE "executed"."id" IS "OLD"."id";
    DELETE FROM "event" WHERE "event"."id" IS "OLD"."id";
  END;

CREATE TRIGGER IF NOT EXISTS "insert_pomodoro" INSTEAD OF INSERT ON "pomodoro_report"
  BEGIN
    INSERT OR IGNORE INTO "tag" ("name") VALUES ("NEW"."tag_name");

    INSERT INTO "event" ("date", "time") VALUES ("NEW"."date", "NEW"."time");

    INSERT INTO "timebox" ("id","duration","description","tag_id")
      VALUES(
        last_insert_rowid(),
        "NEW"."duration",
        "NEW"."description",
        (SELECT "id" FROM "tag" AS "g" WHERE "g"."name" IS "NEW"."tag_name")
      );
  END;

CREATE TRIGGER IF NOT EXISTS "insert_statistics" INSTEAD OF INSERT ON "statistics_report"
  BEGIN
    INSERT OR IGNORE INTO "command_label" ("name") VALUES ("NEW"."label_name");
    INSERT OR IGNORE INTO "status" ("name") VALUES ("NEW"."status");

    INSERT INTO "event" ("date", "time") VALUES ("NEW"."date", "NEW"."time");

    INSERT INTO "executed" ("id", "command_label_id", "status_id", "elapsed_time_in_secs")
      VALUES (
        last_insert_rowid(),
        (SELECT "id" FROM "command_label" AS "c" WHERE "c"."name" IS "NEW"."label_name"),
        (SELECT "id" FROM "status" AS "s" WHERE "s"."name" IS "NEW"."status"),
        "NEW"."elapsed_time_in_secs"
      );
  END;

COMMIT;
