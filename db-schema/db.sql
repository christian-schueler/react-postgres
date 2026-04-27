-- This file contains the SQL statements to create the database schema for the application.
-- It includes the creation of tables, indexes, and any necessary constraints.
-- After creating the schema, some sample data will be inserted to demonstrate the functionality of the application.

-- table creations as inherited tables
-- base table with meta data for all objects
DROP TABLE IF EXISTS "public"."base_object";
CREATE TABLE "public"."base_object" (
  "id" UUID NOT NULL,
  PRIMARY KEY ("id")
);
CREATE INDEX ON "public"."base_object" ("id");
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
  "linked_to" UUID NULL CONSTRAINT "check_parent" CHECK ("parent" IS NULL) REFERENCES "public"."location" ("id"),
  "parent" UUID NULL CONSTRAINT "check_link" CHECK ("linked_to" IS NULL) REFERENCES "public"."specialobject" ("id")
) INHERITS("public"."base_object");
CREATE INDEX ON "public"."specialobject" ("linked_to");
CREATE INDEX ON "public"."specialobject" ("parent");
COMMENT ON TABLE "public"."specialobject" IS 'structural specialobject table';
COMMENT ON COLUMN "public"."specialobject"."linked_to" IS 'reference to a location object';
COMMENT ON COLUMN "public"."specialobject"."parent" IS 'reference to another specialobject';

-- event type table
DROP TABLE IF EXISTS "public"."event_type";
CREATE TABLE "public"."event_type" (
  "id" UUID PRIMARY KEY,
  "name" VARCHAR(255) NOT NULL,
  "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX ON "public"."event_type" ("name");
COMMENT ON TABLE "public"."event_type" IS 'types of events';
COMMENT ON COLUMN "public"."event_type"."name" IS 'name of the event type';
COMMENT ON COLUMN "public"."event_type"."metadata" IS 'event behaviour metadata (e.g. if the event is an event, increasing or decreasing an amount)';

-- global eventsourcing table
DROP TABLE IF EXISTS "public"."events";
CREATE TABLE "public"."events" (
  "global_position" BIGSERIAL PRIMARY KEY,
  "object_id" UUID NOT NULL,
  "object_type" VARCHAR(255) NOT NULL,
  "event_type" UUID NOT NULL REFERENCES "public"."event_type" ("id"),
  "event_version" INTEGER NOT NULL,
  "payload" JSONB NOT NULL,
  "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Optimistic Concurrency Control: prevents concurrent writes to the same object with the same version
  CONSTRAINT "uk_object_version" UNIQUE ("object_id", "event_version")
);

-- index for fast loading of all events of a specific object (e.g. all events for a specific object)
CREATE INDEX "idx_events_stream" ON "public"."events" ("object_id");

-- index for loading all events for an object (e.g. all events for a specific location or specialobject) - optional, depends on query patterns
CREATE INDEX "idx_events_stream_type" ON "public"."events" ("object_type");

-- index for timebased replay of events (e.g. all events since a specific timestamp)
CREATE INDEX "idx_events_created_at" ON "public"."events" ("created_at");

-- optional: index for searching in the payload or metadata of events - depends on query patterns and size of data
CREATE INDEX "idx_events_payload_gin" ON "public"."events" USING GIN ("payload");
CREATE INDEX "idx_events_metadata_gin" ON "public"."events" USING GIN ("metadata");

-- comments for the events table
COMMENT ON TABLE "public"."events" IS 'global eventsourcing table';
COMMENT ON COLUMN "public"."events"."global_position" IS 'absolute running number on all events in the whole system (critical column for event projection)';
COMMENT ON COLUMN "public"."events"."object_id" IS 'unique identifier for the object';
COMMENT ON COLUMN "public"."events"."object_type" IS 'type of the object';
COMMENT ON COLUMN "public"."events"."event_type" IS 'type of the specific event (LeaseContractSigned, RentIncreased, etc.)';
COMMENT ON COLUMN "public"."events"."event_version" IS 'critical column for event writing: must be incremented by 1 for each new event of the same object (critical column for event writing and optimistic concurrency control)';
COMMENT ON COLUMN "public"."events"."payload" IS 'contains the actual data of the event (e.g. the new rent amount, the name of the tenant, etc.)';
COMMENT ON COLUMN "public"."events"."metadata" IS 'metadata like the user_id, IP-address, etc. of the event (optional, depends on the use case)';
COMMENT ON COLUMN "public"."events"."created_at" IS 'timezoned timestamp of the event creation (critical column for timebased event replay)';

-- ACL for object type and subtype or class based permissions
CREATE TABLE "public"."acl_class_permissions" (
  "user_id" UUID NOT NULL,
  "object_type" VARCHAR(255) NOT NULL,
  "object_subtype" VARCHAR(255) NULL,
  "class_id" UUID NULL,
  "action" VARCHAR(100) NOT NULL,
  "granted_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "granted_to" TIMESTAMPTZ NULL DEFAULT NULL,

  -- grant an action to a user for a specific object type and subtype
  -- (e.g. user_id = xyz, object_type = 'location', object_subtype = 'room', "class_id" = NULL, action = 'read' or
  --       user_id = xyz, object_type = 'location', object_subtype = NULL, "class_id" = <class_id>, action = 'read'
  -- means that the user with id xyz has the right to read all objects of type 'location' and subtype 'room' or
  -- all objects of type 'location' and subtype 'room' with the specific class_id)
  PRIMARY KEY ("user_id", "object_type", "object_subtype", "class_id", "action")
);

-- index for fast query of all permissions of a specific user for a specific object type and subtype
CREATE INDEX "idx_acl_class_user" ON "public"."acl_class_permissions" ("user_id");

-- ACL for specified object permissions
-- (e.g. user xyz has the right to read the specific object with object_id abc)
CREATE TABLE "public"."acl_object_permissions" (
  "user_id" UUID NOT NULL,
  "object_id" UUID NOT NULL,
  "object_type" VARCHAR(255) NOT NULL,
  "action" VARCHAR(100) NOT NULL,
  "granted_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "granted_to" TIMESTAMPTZ NULL DEFAULT NULL,

  -- grant an action to a user for a specific object
  PRIMARY KEY ("user_id", "object_id", "action")
);

-- index for fast check, if a user has access to a specific object
CREATE INDEX "idx_acl_object_user_stream" ON "public"."acl_object_permissions" ("user_id", "object_id");
-- index, to query all objects, a user has a specific action permission for (important for read models/lists)
CREATE INDEX "idx_acl_object_user_action" ON "public"."acl_object_permissions" ("user_id", "action");
