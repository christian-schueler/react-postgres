-- This file contains the SQL statements to create the database schema for the application.
-- It includes the creation of tables, indexes, and any necessary constraints.
-- After creating the schema, some sample data will be inserted to demonstrate the functionality of the application.

-- base table with meta data for all objects
DROP TABLE IF EXISTS "public"."p_base_object";
CREATE TABLE "public"."p_base_object" (
  "id" UUID NOT NULL PRIMARY KEY
);
CREATE INDEX ON "public"."p_base_object" ("id");
COMMENT ON TABLE "public"."p_base_object" IS 'basic object table';

-- event type table
DROP TABLE IF EXISTS "public"."c_event_type";
CREATE TABLE "public"."c_event_type" (
  "id" UUID PRIMARY KEY,
  "name" VARCHAR(255) NOT NULL,
  "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX ON "public"."c_event_type" ("name");
COMMENT ON TABLE "public"."c_event_type" IS 'types of events';
COMMENT ON COLUMN "public"."c_event_type"."name" IS 'name of the event type';
COMMENT ON COLUMN "public"."c_event_type"."metadata" IS 'event behaviour metadata (e.g. if the event is an event, increasing or decreasing an amount)';

-- global eventsourcing table
DROP TABLE IF EXISTS "public"."p_events";
CREATE TABLE "public"."p_events" (
  "global_position" BIGSERIAL PRIMARY KEY,
  "object_id" UUID NOT NULL REFERENCES "public"."p_base_object"("id") ON DELETE CASCADE,
  "object_type" VARCHAR(255) NOT NULL,
  "event_type" UUID NOT NULL REFERENCES "public"."c_event_type" ("id") ON DELETE CASCADE,
  "event_version" INTEGER NOT NULL,
  "payload" JSONB NOT NULL,
  "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Optimistic Concurrency Control: prevents concurrent writes to the same object with the same version
  CONSTRAINT "uk_object_version" UNIQUE ("object_id", "event_version")
);

-- index for fast loading of all events of a specific object (e.g. all events for a specific object)
CREATE INDEX "idx_events_object_id" ON "public"."p_events" ("object_id");

-- index for loading all events for an object (e.g. all events for a specific location or specialobject) - optional, depends on query patterns
CREATE INDEX "idx_events_object_type" ON "public"."p_events" ("object_type");

-- index for timebased replay of events (e.g. all events since a specific timestamp)
CREATE INDEX "idx_events_created_at" ON "public"."p_events" ("created_at");

-- optional: index for searching in the payload or metadata of events - depends on query patterns and size of data
CREATE INDEX "idx_events_payload_gin" ON "public"."p_events" USING GIN ("payload");
CREATE INDEX "idx_events_metadata_gin" ON "public"."p_events" USING GIN ("metadata");

-- comments for the events table
COMMENT ON TABLE "public"."p_events" IS 'global eventsourcing table';
COMMENT ON COLUMN "public"."p_events"."global_position" IS 'absolute running number on all events in the whole system (critical column for event projection)';
COMMENT ON COLUMN "public"."p_events"."object_id" IS 'unique identifier for the object';
COMMENT ON COLUMN "public"."p_events"."object_type" IS 'type of the object';
COMMENT ON COLUMN "public"."p_events"."event_type" IS 'type of the specific event (LeaseContractSigned, RentIncreased, etc.)';
COMMENT ON COLUMN "public"."p_events"."event_version" IS 'critical column for event writing: must be incremented by 1 for each new event of the same object (critical column for event writing and optimistic concurrency control)';
COMMENT ON COLUMN "public"."p_events"."payload" IS 'contains the actual data of the event (e.g. the new rent amount, the name of the tenant, etc.)';
COMMENT ON COLUMN "public"."p_events"."metadata" IS 'metadata like the user_id, IP-address, etc. of the event (optional, depends on the use case)';
COMMENT ON COLUMN "public"."p_events"."created_at" IS 'timezoned timestamp of the event creation (critical column for timebased event replay)';

-- structural location table
DROP TABLE IF EXISTS "public"."p_location";
CREATE TABLE "public"."p_location" (
  "id" UUID NOT NULL PRIMARY KEY REFERENCES "public"."p_base_object"("id") ON DELETE CASCADE,
  "parent" UUID NULL
);
CREATE INDEX ON "public"."p_location" ("parent");
COMMENT ON TABLE "public"."p_location" IS 'structural location table';

-- structural specialobject table
DROP TABLE IF EXISTS "public"."p_specialobject";
CREATE TABLE "public"."p_specialobject" (
  "id" UUID NOT NULL PRIMARY KEY REFERENCES "public"."p_base_object"("id") ON DELETE CASCADE,
  "linked_to" UUID NULL CONSTRAINT "check_parent" CHECK ("parent" IS NULL) REFERENCES "public"."p_location" ("id") ON DELETE SET NULL ("linked_to"),
  "parent" UUID NULL CONSTRAINT "check_link" CHECK ("linked_to" IS NULL) REFERENCES "public"."p_specialobject" ("id") ON DELETE SET NULL ("parent")
);
CREATE INDEX ON "public"."p_specialobject" ("linked_to");
CREATE INDEX ON "public"."p_specialobject" ("parent");
COMMENT ON TABLE "public"."p_specialobject" IS 'structural specialobject table';
COMMENT ON COLUMN "public"."p_specialobject"."linked_to" IS 'reference to a location object';
COMMENT ON COLUMN "public"."p_specialobject"."parent" IS 'reference to another specialobject';

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
CREATE INDEX "idx_acl_object_user_object" ON "public"."acl_object_permissions" ("user_id", "object_id");
-- index, to query all objects, a user has a specific action permission for (important for read models/lists)
CREATE INDEX "idx_acl_object_user_action" ON "public"."acl_object_permissions" ("user_id", "action");
