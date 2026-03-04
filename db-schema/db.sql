-- This file contains the SQL statements to create the database schema for the application.
-- It includes the creation of tables, indexes, and any necessary constraints.
-- After creating the schema, some sample data will be inserted to demonstrate the functionality of the application.

-- table creations as inherited tables
-- base table with meta data for all objects
DROP TABLE IF EXISTS "public"."base_object";
CREATE TABLE "public"."base_object" (
  "id" UUID NOT NULL,
  "start" timestamp NOT NULL,
  "end" timestamp NULL,
  "archived" boolean GENERATED ALWAYS AS ("end" IS NOT NULL),
  "creator" UUID NOT NULL,
  "created_at" TIMESTAMP NOT NULL,
  "updater" UUID NULL,
  "updated_at" TIMESTAMP NULL,
  PRIMARY KEY ("id","start","end")
);
CREATE INDEX ON "public"."base_object" ("id");
CREATE INDEX ON "public"."base_object" ("start");
CREATE INDEX ON "public"."base_object" ("end");
CREATE INDEX ON "public"."base_object" ("id", "start");
CREATE INDEX ON "public"."base_object" ("id", "end");
CREATE INDEX ON "public"."base_object" ("creator");
CREATE INDEX ON "public"."base_object" ("created_at");
CREATE INDEX ON "public"."base_object" ("updater");
CREATE INDEX ON "public"."base_object" ("updated_at");
COMMENT ON TABLE "public"."base_object" IS 'basic object table with timestamps for valid state';

-- structural location table
DROP TABLE IF EXISTS "public"."location";
CREATE TABLE "public"."location" (
  "parent" UUID NULL
) INHERITS("public"."base_object");
CREATE INDEX ON "public"."location" ("parent");
COMMENT ON TABLE "public"."location" IS 'structural location table';

-- structural specialobject table
DROP TABLE IF EXISTS "public"."specialobject";
CREATE TABLE "public"."specialobject" (
  "parent" UUID NULL CONSTRAINT "check_link" CHECK ("linked_to" IS NULL),
  "linked_to" UUID NULL CONSTRAINT "check_parent" CHECK ("parent" IS NULL)
) INHERITS("public"."base_object");
CREATE INDEX ON "public"."specialobject" ("parent");
CREATE INDEX ON "public"."specialobject" ("linked_to");
COMMENT ON TABLE "public"."specialobject" IS 'structural specialobject table';
