


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."create_features_layers"("_features" "json", "_srid" integer, "_project_id" "uuid", "_user_id" "uuid") RETURNS TABLE("layer_id" "uuid", "feature_id" "uuid")
    LANGUAGE "plpgsql"
    AS $$DECLARE
  rec            RECORD;
  points_layer   UUID;
  new_layer_id   UUID;
  new_feature_id UUID;

   point_style TEXT := '"{\"iconRetinaUrl\":\"/images/icons/2/circle/blue/iconx2.png\",\"iconUrl\":\"/images/icons/2/circle/blue/icon.png\",\"iconSize\":[42,45],\"iconAnchor\":[21,44],\"shadowUrl\":\"/images/iconShadow1.png\",\"shadowSize\":[70,17],\"shadowAnchor\":[35,7],\"popupAnchor\":[0,-40]}"';

  line_style TEXT := '"{\"stroke\":true,\"color\":\"#219EBC\",\"weight\":2,\"opacity\":1,\"lineCap\":\"round\",\"lineJoin\":\"miter\",\"dashArray\":[8,4],\"fill\":true,\"fillColor\":\"#219EBC\",\"fillOpacity\":0.3}"';

BEGIN
  -----------------------------------------------
  -- 1) Create one single “MULTIPOINTS” layer for ALL incoming POINT features
  -----------------------------------------------
  INSERT INTO layers (name, geom_type, srid, style, project_id, user_id)
  VALUES (
    'MULTIPOINTS',
    'POINT',
    _srid,
    point_style::jsonb,
    _project_id,
    _user_id
  )
  RETURNING id INTO points_layer;

  -----------------------------------------------
  -- 2) Loop over each JSON element in _features
  -----------------------------------------------
  FOR rec IN
    SELECT
      (x->>'geomType')::TEXT   AS geom_type,
      (x->>'wkt')::TEXT        AS wkt,
      (x->>'elevation')::DOUBLE PRECISION   AS elevation
    FROM json_array_elements(_features) AS arr(x)
  LOOP
    CASE rec.geom_type
      WHEN 'POINT' THEN
        INSERT INTO point_features (geom, elevation, layer_id, user_id)
        VALUES (
          ST_GeomFromText(rec.wkt, 4326),
          rec.elevation,
          points_layer,
          _user_id
        )
        RETURNING id INTO new_feature_id;

        layer_id := points_layer;
        feature_id := new_feature_id;
        RETURN NEXT;

      WHEN 'POLYLINE' THEN
        INSERT INTO layers (name, geom_type, srid, style, project_id, user_id)
        VALUES (
          'POLYLINE',
          'POLYLINE',
          _srid,
          line_style::jsonb,
          _project_id,
          _user_id
        )
        RETURNING id INTO new_layer_id;

        INSERT INTO polyline_features (geom, layer_id, user_id)
        VALUES (
          ST_GeomFromText(rec.wkt, 4326),
          new_layer_id,
          _user_id
        )
        RETURNING id INTO new_feature_id;

        layer_id := new_layer_id;
        feature_id := new_feature_id;
        RETURN NEXT;

      WHEN 'POLYGON' THEN
        INSERT INTO layers (name, geom_type, srid, style, project_id, user_id)
        VALUES (
          'POLYGON',
          'POLYGON',
          _srid,
          line_style::jsonb,
          _project_id,
          _user_id
        )
        RETURNING id INTO new_layer_id;

        INSERT INTO polygon_features (geom, layer_id, user_id)
        VALUES (
          ST_GeomFromText(rec.wkt, 4326),
          new_layer_id,
          _user_id
        )
        RETURNING id INTO new_feature_id;

        layer_id := new_layer_id;
        feature_id := new_feature_id;
        RETURN NEXT;

      ELSE
        RAISE EXCEPTION 'Invalid geometry type: %', rec.geom_type;
    END CASE;
  END LOOP;

  RETURN;
END;$$;


ALTER FUNCTION "public"."create_features_layers"("_features" "json", "_srid" integer, "_project_id" "uuid", "_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_layer_with_feature"("layer_name" "text", "wkt" "text", "geom_type" "text", "project_id" "uuid", "user_id" "uuid", "elevation" numeric DEFAULT NULL::numeric, "style" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("layer_id" "uuid", "feature_id" "uuid")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  new_layer_id UUID;
  new_feature_id UUID;
BEGIN
  INSERT INTO layers (name, geom_type, style, project_id, user_id)
  VALUES (layer_name, geom_type, style, project_id, user_id)
  RETURNING id INTO new_layer_id;

  CASE geom_type
    WHEN 'POINT' THEN
       INSERT INTO point_features (geom, elevation, layer_id, user_id)
      VALUES (
        ST_GeomFromText(wkt, 4326),
        elevation,
        new_layer_id, 
        user_id
      )
      RETURNING id INTO new_feature_id;
    WHEN 'POLYGON' THEN
      INSERT INTO polygon_features (geom, layer_id, user_id)
      VALUES (ST_GeomFromText(wkt, 4326), new_layer_id, user_id)
      RETURNING id INTO new_feature_id;
    WHEN 'POLYLINE' THEN
      INSERT INTO polyline_features (geom, layer_id, user_id)
      VALUES (ST_GeomFromText(wkt, 4326), new_layer_id, user_id)
      RETURNING id INTO new_feature_id;
    ELSE
      RAISE EXCEPTION 'Invalid geometry type: %', geom_type;
  END CASE;

  RETURN QUERY SELECT new_layer_id, new_feature_id;
END;
$$;


ALTER FUNCTION "public"."create_layer_with_feature"("layer_name" "text", "wkt" "text", "geom_type" "text", "project_id" "uuid", "user_id" "uuid", "elevation" numeric, "style" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_point_edges_layer"("_project_id" "uuid", "_user_id" "uuid", "_features" "json", "_style" "json") RETURNS TABLE("layer_id" "uuid", "feature_id" "uuid")
    LANGUAGE "plpgsql"
    AS $$DECLARE
  rec  RECORD;
BEGIN
  -- 1) create the layer
  INSERT INTO layers (name, geom_type, style, project_id, user_id)
  VALUES ('MULTIPOINTS','POINT',_style, _project_id, _user_id)
  RETURNING id INTO layer_id;
  
  -- 2) loop through the JSON array
  FOR rec IN
    SELECT wkt, elevation
    FROM   json_to_recordset(_features)
           AS x(wkt TEXT, elevation REAL)
  LOOP
    INSERT INTO point_features (geom, elevation, layer_id, user_id)
    VALUES (
      ST_GeomFromText(rec.wkt, 4326),
      rec.elevation,
      layer_id,
      _user_id
    )
    RETURNING id INTO feature_id;
    
    RETURN NEXT;  -- emit each (layer_id, feature_id) pair
  END LOOP;
END;$$;


ALTER FUNCTION "public"."create_point_edges_layer"("_project_id" "uuid", "_user_id" "uuid", "_features" "json", "_style" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_layer_and_features"("p_layer_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Delete point features
  DELETE FROM point_features
  WHERE layer_id = p_layer_id;

  -- Delete polyline features
  DELETE FROM polyline_features
  WHERE layer_id = p_layer_id;

  -- Delete polygon features
  DELETE FROM polygon_features
  WHERE layer_id = p_layer_id;

  -- Finally delete the layer itself
  DELETE FROM layers
  WHERE id = p_layer_id;
END;
$$;


ALTER FUNCTION "public"."delete_layer_and_features"("p_layer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_layer_images"("p_layer_id" "uuid", "p_image_url" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  
    UPDATE public.layers
    SET image_url = array_remove(image_url, p_image_url)
    WHERE id = p_layer_id;
  
  -- If no row was updated, it means the layer ID didn’t exist
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Layer % does not exist', p_layer_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."delete_layer_images"("p_layer_id" "uuid", "p_image_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_layer_by_id"("p_layer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  _layer JSONB;
BEGIN
  SELECT jsonb_build_object(
    'id',         l.id,
    'name',       l.name,
    'geom_type',  l.geom_type,
    'srid',       l.srid,
    'is_disabled',l.is_disabled,
    'style',      l.style,
    'features',
      CASE l.geom_type
      WHEN 'POINT' THEN (
        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'id',        pf.id,
              'x',         ROUND(CAST(ST_X(ST_Transform(pf.geom, l.srid)) AS numeric), 6),
              'y',         ROUND(CAST(ST_Y(ST_Transform(pf.geom, l.srid)) AS numeric), 6),
              'elevation', pf.elevation
            )
          ),
          '[]'::JSONB
        )
        FROM point_features pf
        WHERE pf.layer_id = l.id
      )
      WHEN 'POLYLINE' THEN (
        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'id',       pl.id,
              'length_m', ROUND(CAST(ST_Length(pl.geom::geography) AS numeric), 2)
            )
          ),
          '[]'::JSONB
        )
        FROM polyline_features pl
        WHERE pl.layer_id = l.id
      )
      WHEN 'POLYGON' THEN (
        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'id',         pg.id,
              'surface_m2', ROUND(CAST(ST_Area(pg.geom::geography) AS numeric), 2),
              'surface_ha', ROUND(CAST(ST_Area(pg.geom::geography) / 10000.0 AS numeric), 4),
              'surface_ca', ROUND(CAST(ST_Area(pg.geom::geography) / 100.0 AS numeric), 2)
            )
          ),
          '[]'::JSONB
        )
        FROM polygon_features pg
        WHERE pg.layer_id = l.id
      )
      ELSE '[]'::JSONB
      END
  ) INTO _layer
  FROM layers l
  WHERE l.id = p_layer_id
  LIMIT 1;

  RETURN COALESCE(_layer, '{}'::JSONB);
END;
$$;


ALTER FUNCTION "public"."get_layer_by_id"("p_layer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_layers_coords"("p_project_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$DECLARE
  _layers JSONB;
BEGIN
  SELECT jsonb_agg(layer_obj) INTO _layers
  FROM (
    SELECT
      l.id,
      l.name,
      l.geom_type,
      l.srid,
      l.image_url,
      l.description,
      l.is_disabled,
      l.style,
      l.created_at,
      CASE
        WHEN l.geom_type = 'POINT' THEN (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id',         pf.id,
              'coordinates', jsonb_build_array(
                                ROUND(CAST(ST_Y(pf.geom) AS numeric), 6),
                                ROUND(CAST(ST_X(pf.geom) AS numeric), 6)
                              ),
              'x',          ST_X(ST_Transform(pf.geom, l.srid)),
              'y',          ST_Y(ST_Transform(pf.geom, l.srid)),
              'elevation',  pf.elevation,
              'updated_at', pf.updated_at

            )
          )
          FROM point_features pf
          WHERE pf.layer_id = l.id
        )

        WHEN l.geom_type = 'POLYLINE' THEN (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id',          pl.id,
              'coordinates', (
                SELECT jsonb_agg(
                  jsonb_build_array(
                    ROUND(CAST(ST_Y((dp).geom) AS numeric), 6),
                    ROUND(CAST(ST_X((dp).geom) AS numeric), 6)
                  )
                )
                FROM ST_DumpPoints(pl.geom) AS dp
              ),
              
              'length_m',    ROUND(CAST(ST_Length(pl.geom::geography) AS numeric), 2),
              'updated_at', pl.updated_at
            )
          )
          FROM polyline_features pl
          WHERE pl.layer_id = l.id
        )

        WHEN l.geom_type = 'POLYGON' THEN (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id',           pg.id,
              'coordinates',  jsonb_build_array(
                  (
                    SELECT jsonb_agg(
                      jsonb_build_array(
                        ROUND(CAST(ST_Y((dp).geom) AS numeric), 6),
                        ROUND(CAST(ST_X((dp).geom) AS numeric), 6)
                      )
                    )
                    FROM ST_DumpPoints(
                      ST_ExteriorRing(pg.geom)
                    ) AS dp
                  )
                ),
              'surface_m2',   ROUND(CAST(ST_Area(pg.geom::geography) AS numeric), 2),
              'surface_ha',   ROUND(CAST(ST_Area(pg.geom::geography) / 10000.0 AS numeric), 4),
              'surface_ca',   ROUND(CAST(ST_Area(pg.geom::geography) / 100.0 AS numeric), 2),
              'updated_at', pg.updated_at
            )
          )
          FROM polygon_features pg
          WHERE pg.layer_id = l.id
        )

        ELSE '[]'::JSONB
      END AS features
    FROM layers l
    WHERE l.project_id = p_project_id
    ORDER BY l.created_at DESC
  ) AS layer_obj;

  RETURN COALESCE(_layers, '[]'::JSONB);
END;$$;


ALTER FUNCTION "public"."get_project_layers_coords"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_audit_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  excluded_columns TEXT[] := ARRAY['updated_at', 'created_at'];
  user_uuid UUID;
BEGIN
  -- Get user ID from JWT claims with UUID conversion
  user_uuid := (current_setting('request.jwt.claims', true)::json->>'sub')::UUID;

  IF (TG_OP = 'DELETE') THEN
    INSERT INTO audit_logs (
      action_type,
      table_name,
      record_id,
      user_id,
      old_data,
      client_ip,
      client_agent
    )
    VALUES (
      'DELETE',
      TG_TABLE_NAME,
      OLD.id,
      user_uuid,  -- Use converted UUID
      to_jsonb(OLD),
      current_setting('request.headers', true)::json->>'x-real-ip',
      current_setting('request.headers', true)::json->>'user-agent'
    );
    RETURN OLD;
  
  ELSIF (TG_OP = 'UPDATE') THEN
    INSERT INTO audit_logs (
      action_type,
      table_name,
      record_id,
      user_id,
      old_data,
      new_data,
      client_ip,
      client_agent
    )
    VALUES (
      'UPDATE',
      TG_TABLE_NAME,
      NEW.id,
      user_uuid,  -- Use converted UUID
      to_jsonb(OLD) - excluded_columns,
      to_jsonb(NEW) - excluded_columns,
      current_setting('request.headers', true)::json->>'x-real-ip',
      current_setting('request.headers', true)::json->>'user-agent'
    );
    RETURN NEW;
  
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO audit_logs (
      action_type,
      table_name,
      record_id,
      user_id,
      new_data,
      client_ip,
      client_agent
    )
    VALUES (
      'INSERT',
      TG_TABLE_NAME,
      NEW.id,
      user_uuid,  -- Use converted UUID
      to_jsonb(NEW) - excluded_columns,
      current_setting('request.headers', true)::json->>'x-real-ip',
      current_setting('request.headers', true)::json->>'user-agent'
    );
    RETURN NEW;
  END IF;
  
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."log_audit_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_layer_image"("p_layer_id" "uuid", "p_image_url" "text", "p_overwrite" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF p_overwrite THEN
    UPDATE public.layers
      SET image_url = ARRAY[p_image_url]
      WHERE id = p_layer_id;
  ELSE
    UPDATE public.layers
      SET image_url = COALESCE(image_url, ARRAY[]::text[]) || p_image_url
      WHERE id = p_layer_id;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Layer % does not exist', p_layer_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."save_layer_image"("p_layer_id" "uuid", "p_image_url" "text", "p_overwrite" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_feature_geometry"("_layer_id" "uuid", "_feature_id" "uuid", "_wkt" "text", "_elevation" numeric DEFAULT NULL::numeric) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  _geom_type   TEXT;
BEGIN
  -- fetch layer type
  SELECT geom_type INTO _geom_type
    FROM layers WHERE id = _layer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Layer % does not exist', _layer_id;
  END IF;

  -- route update by type
  CASE _geom_type
    WHEN 'POINT' THEN
      UPDATE point_features
         SET geom      = ST_SetSRID(ST_GeomFromText(_wkt), 4326),
             elevation = COALESCE(_elevation, elevation)
       WHERE id = _feature_id AND layer_id = _layer_id;
    WHEN 'POLYGON' THEN
      UPDATE polygon_features
         SET geom = ST_SetSRID(ST_GeomFromText(_wkt), 4326)
       WHERE id = _feature_id AND layer_id = _layer_id;
    WHEN 'POLYLINE' THEN
      UPDATE polyline_features
         SET geom = ST_SetSRID(ST_GeomFromText(_wkt), 4326)
       WHERE id = _feature_id AND layer_id = _layer_id;
    ELSE
      RAISE EXCEPTION 'Unsupported geom_type "%"', _geom_type;
  END CASE;

  IF NOT FOUND THEN
    RAISE NOTICE 'No feature % found for layer %', _feature_id, _layer_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."update_feature_geometry"("_layer_id" "uuid", "_feature_id" "uuid", "_wkt" "text", "_elevation" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_features_geometries"("p_updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  rec RECORD;   -- ← must match "row" target of FOR ... IN
BEGIN
  FOR rec IN
    SELECT
      (elem->>'layer_id')::uuid     AS layer_id,
      (elem->>'feature_id')::uuid    AS feature_id,
      elem->>'wkt'                   AS wkt,
      CASE WHEN elem->>'elevation' IS NULL
           THEN NULL
           ELSE (elem->>'elevation')::numeric
      END                            AS elevation
    FROM jsonb_array_elements(p_updates) AS arr(elem)
  LOOP
    PERFORM update_feature_geometry(
      rec.layer_id,
      rec.feature_id,
      rec.wkt,
      rec.elevation
    );
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."update_features_geometries"("p_updates" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_modified_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_modified_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "action_type" "text" NOT NULL,
    "table_name" "text" NOT NULL,
    "record_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "old_data" "jsonb",
    "new_data" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "client_ip" "text",
    "client_agent" "text",
    CONSTRAINT "audit_logs_action_type_check" CHECK (("action_type" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"])))
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."layers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "geom_type" "text" NOT NULL,
    "srid" integer DEFAULT 4326 NOT NULL,
    "is_disabled" boolean DEFAULT false NOT NULL,
    "style" "jsonb",
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "description" character varying,
    "image_url" "text"[],
    CONSTRAINT "layers_geom_type_check" CHECK (("geom_type" = ANY (ARRAY['POINT'::"text", 'POLYGON'::"text", 'POLYLINE'::"text"])))
);


ALTER TABLE "public"."layers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."point_features" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "geom" "extensions"."geometry"(Point,4326) NOT NULL,
    "layer_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "elevation" numeric(8,3)
);


ALTER TABLE "public"."point_features" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."polygon_features" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "geom" "extensions"."geometry"(Polygon,4326) NOT NULL,
    "layer_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."polygon_features" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."polyline_features" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "geom" "extensions"."geometry"(LineString,4326) NOT NULL,
    "layer_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."polyline_features" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."layers"
    ADD CONSTRAINT "layers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."point_features"
    ADD CONSTRAINT "point_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."polygon_features"
    ADD CONSTRAINT "polygon_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."polyline_features"
    ADD CONSTRAINT "polyline_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_audit_action_type" ON "public"."audit_logs" USING "btree" ("action_type");



CREATE INDEX "idx_audit_table_record" ON "public"."audit_logs" USING "btree" ("table_name", "record_id");



CREATE INDEX "idx_audit_user_time" ON "public"."audit_logs" USING "btree" ("user_id", "created_at");



CREATE INDEX "idx_layers_project" ON "public"."layers" USING "btree" ("project_id");



CREATE INDEX "idx_point_features_layer" ON "public"."point_features" USING "btree" ("layer_id");



CREATE INDEX "idx_point_geom" ON "public"."point_features" USING "gist" ("geom");



CREATE INDEX "idx_polygon_features_layer" ON "public"."polygon_features" USING "btree" ("layer_id");



CREATE INDEX "idx_polygon_geom" ON "public"."polygon_features" USING "gist" ("geom");



CREATE INDEX "idx_polyline_features_layer" ON "public"."polyline_features" USING "btree" ("layer_id");



CREATE INDEX "idx_polyline_geom" ON "public"."polyline_features" USING "gist" ("geom");



CREATE INDEX "idx_projects_user" ON "public"."projects" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "layers_audit_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."layers" FOR EACH ROW EXECUTE FUNCTION "public"."log_audit_event"();



CREATE OR REPLACE TRIGGER "point_features_audit_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."point_features" FOR EACH ROW EXECUTE FUNCTION "public"."log_audit_event"();



CREATE OR REPLACE TRIGGER "polygon_features_audit_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."polygon_features" FOR EACH ROW EXECUTE FUNCTION "public"."log_audit_event"();



CREATE OR REPLACE TRIGGER "polyline_features_audit_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."polyline_features" FOR EACH ROW EXECUTE FUNCTION "public"."log_audit_event"();



CREATE OR REPLACE TRIGGER "update_layers_modtime" BEFORE UPDATE ON "public"."layers" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



CREATE OR REPLACE TRIGGER "update_point_features_modtime" BEFORE UPDATE ON "public"."point_features" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



CREATE OR REPLACE TRIGGER "update_polygon_features_modtime" BEFORE UPDATE ON "public"."polygon_features" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



CREATE OR REPLACE TRIGGER "update_polyline_features_modtime" BEFORE UPDATE ON "public"."polyline_features" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



CREATE OR REPLACE TRIGGER "update_projects_modtime" BEFORE UPDATE ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."layers"
    ADD CONSTRAINT "layers_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."layers"
    ADD CONSTRAINT "layers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."point_features"
    ADD CONSTRAINT "point_features_layer_id_fkey" FOREIGN KEY ("layer_id") REFERENCES "public"."layers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."point_features"
    ADD CONSTRAINT "point_features_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."polygon_features"
    ADD CONSTRAINT "polygon_features_layer_id_fkey" FOREIGN KEY ("layer_id") REFERENCES "public"."layers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."polygon_features"
    ADD CONSTRAINT "polygon_features_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."polyline_features"
    ADD CONSTRAINT "polyline_features_layer_id_fkey" FOREIGN KEY ("layer_id") REFERENCES "public"."layers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."polyline_features"
    ADD CONSTRAINT "polyline_features_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



CREATE POLICY "Allow audit log writes" ON "public"."audit_logs" FOR INSERT WITH CHECK (true);



CREATE POLICY "Audit logs admin access" ON "public"."audit_logs" USING ((EXISTS ( SELECT 1
   FROM "auth"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ((("users"."role")::"text" = 'admin'::"text") OR (("users"."email")::"text" = 'admin@example.com'::"text")))))) WITH CHECK (false);



CREATE POLICY "User access to own points" ON "public"."point_features" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "User access to own polygons" ON "public"."polygon_features" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "User access to own polylines" ON "public"."polyline_features" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "User can access project layers" ON "public"."layers" USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "layers"."project_id") AND ("projects"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "layers"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "User can manage their projects" ON "public"."projects" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."layers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."point_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."polygon_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."polyline_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."create_features_layers"("_features" "json", "_srid" integer, "_project_id" "uuid", "_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_features_layers"("_features" "json", "_srid" integer, "_project_id" "uuid", "_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_features_layers"("_features" "json", "_srid" integer, "_project_id" "uuid", "_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_layer_with_feature"("layer_name" "text", "wkt" "text", "geom_type" "text", "project_id" "uuid", "user_id" "uuid", "elevation" numeric, "style" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_layer_with_feature"("layer_name" "text", "wkt" "text", "geom_type" "text", "project_id" "uuid", "user_id" "uuid", "elevation" numeric, "style" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_layer_with_feature"("layer_name" "text", "wkt" "text", "geom_type" "text", "project_id" "uuid", "user_id" "uuid", "elevation" numeric, "style" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_point_edges_layer"("_project_id" "uuid", "_user_id" "uuid", "_features" "json", "_style" "json") TO "anon";
GRANT ALL ON FUNCTION "public"."create_point_edges_layer"("_project_id" "uuid", "_user_id" "uuid", "_features" "json", "_style" "json") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_point_edges_layer"("_project_id" "uuid", "_user_id" "uuid", "_features" "json", "_style" "json") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_layer_and_features"("p_layer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_layer_and_features"("p_layer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_layer_and_features"("p_layer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_layer_images"("p_layer_id" "uuid", "p_image_url" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_layer_images"("p_layer_id" "uuid", "p_image_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_layer_images"("p_layer_id" "uuid", "p_image_url" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_layer_by_id"("p_layer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_layer_by_id"("p_layer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_layer_by_id"("p_layer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_layers_coords"("p_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_layers_coords"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_layers_coords"("p_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_audit_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_audit_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_audit_event"() TO "service_role";



GRANT ALL ON FUNCTION "public"."save_layer_image"("p_layer_id" "uuid", "p_image_url" "text", "p_overwrite" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."save_layer_image"("p_layer_id" "uuid", "p_image_url" "text", "p_overwrite" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_layer_image"("p_layer_id" "uuid", "p_image_url" "text", "p_overwrite" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_feature_geometry"("_layer_id" "uuid", "_feature_id" "uuid", "_wkt" "text", "_elevation" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."update_feature_geometry"("_layer_id" "uuid", "_feature_id" "uuid", "_wkt" "text", "_elevation" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_feature_geometry"("_layer_id" "uuid", "_feature_id" "uuid", "_wkt" "text", "_elevation" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_features_geometries"("p_updates" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_features_geometries"("p_updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_features_geometries"("p_updates" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "service_role";


























































































GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."audit_logs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."audit_logs" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."audit_logs" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."layers" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."layers" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."layers" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."point_features" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."point_features" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."point_features" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polygon_features" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polygon_features" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polygon_features" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polyline_features" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polyline_features" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."polyline_features" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."projects" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."projects" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."projects" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "service_role";































