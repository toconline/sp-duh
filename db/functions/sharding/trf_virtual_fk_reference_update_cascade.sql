-- JOANA: tested on public.tax_exemption_reasons / pt999999990_c2425.efatura_supplier_configurations
-- DROP FUNCTION IF EXISTS sharding.trf_virtual_fk_reference_update_cascade();
CREATE OR REPLACE FUNCTION sharding.trf_virtual_fk_reference_update_cascade()
RETURNS TRIGGER AS $BODY$
DECLARE
  _current_cluster integer;
  specific_company_id integer;
  specific_schema_name TEXT;
  company_schema_name TEXT;
  referencing_columns TEXT[];
  referencing_table TEXT;
  referenced_columns TEXT[];
  referenced_values TEXT[];
  new_values TEXT[];
  trigger_condition_clause TEXT;
  query TEXT;
BEGIN
  -- RAISE DEBUG 'sharding.trf_virtual_fk_reference_update_cascade() TG_NAME:% TG_TABLE_SCHEMA:% TG_TABLE_NAME:% TG_NARGS:% TG_ARGV:%', TG_NAME, TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_NARGS, TG_ARGV;
  -- RAISE DEBUG 'sharding.trf_virtual_fk_reference_update_cascade() -        OLD: %', OLD;

  referencing_columns := TG_ARGV[0];
  referencing_table := TG_ARGV[1];
  referenced_columns := TG_ARGV[2];
  trigger_condition_clause := TG_ARGV[3];

  -- Extract the values from the OLD record into the referenced_values variable
  EXECUTE format(
    format('SELECT ARRAY[%s]::TEXT[]',
      (SELECT array_to_string((SELECT array_agg('($1).%I'::TEXT) FROM (SELECT generate_series(1::integer, array_length(referenced_columns, 1)::integer)) bogus), ', '))
    ),
    VARIADIC referenced_columns
  ) USING OLD INTO referenced_values;

  -- Extract the values from the NEW record into the new_values variable
  EXECUTE format(
    format('SELECT ARRAY[%s]::TEXT[]',
      (SELECT array_to_string((SELECT array_agg('($1).%I'::TEXT) FROM (SELECT generate_series(1::integer, array_length(referenced_columns, 1)::integer)) bogus), ', '))
    ),
    VARIADIC referenced_columns
  ) USING NEW INTO new_values;

  -- Try to get the company schema from the referencing table (in case it's supplied as <schema>.<table>)
  IF (SELECT EXISTS (SELECT 1 FROM regexp_matches(referencing_table, '^.+\..+$'))) THEN
    SELECT (regexp_matches(referencing_table, '^(.+?)\..+?'))[1] INTO specific_schema_name;
    SELECT regexp_replace(referencing_table, specific_schema_name || '.', '') INTO referencing_table;
  ELSIF ( sharding.get_auxiliary_table_information()->'unsharded_tables' ? referencing_table ) THEN
    specific_schema_name := 'public';
  ELSIF TG_TABLE_NAME = 'companies' THEN
    specific_company_id := OLD.id;
  ELSE
    BEGIN
      specific_company_id := OLD.company_id;
      EXCEPTION
        WHEN undefined_column THEN
          specific_company_id := NULL;
    END;
  END IF;

  SHOW cloudware.cluster INTO _current_cluster;
  FOR company_schema_name IN
    SELECT pg_namespace.nspname
      FROM pg_catalog.pg_class
      JOIN pg_catalog.pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      LEFT JOIN public.companies ON NOT companies.is_deleted AND companies.schema_name = pg_namespace.nspname AND companies.cluster = _current_cluster
     WHERE pg_class.relkind = 'r' AND pg_class.relname = referencing_table
       AND ( pg_namespace.nspname = 'public' OR companies.id IS NOT NULL )
       AND ( specific_schema_name IS NULL OR pg_namespace.nspname = specific_schema_name )
       AND ( specific_company_id IS NULL OR companies.id = specific_company_id )
  LOOP
    -- RAISE DEBUG 'company_schema_name = %', company_schema_name;
    query := format('UPDATE %1$I.%2$I SET %3$s WHERE %4$s',
      company_schema_name,
      referencing_table,
      array_to_string((select array_agg(format('%1$I = %2$L', filters.column_name, filters.column_value)) from (SELECT unnest(referencing_columns) as column_name, unnest(new_values) as column_value) filters), ', '),
      array_to_string((select array_agg(format('%1$I = %2$L', filters.column_name, filters.column_value)) from (SELECT unnest(referencing_columns) as column_name, unnest(referenced_values) as column_value) filters), ' AND ')
    );

    IF trigger_condition_clause IS NOT NULL THEN
      query := query || ' AND ' || trigger_condition_clause;
    END IF;

    -- RAISE DEBUG 'query: %', query;
    EXECUTE query;
  END LOOP;

  -- RAISE DEBUG 'sharding.trf_virtual_fk_reference_update_cascade() - RETURN NEW: %', NEW;
  RETURN NEW;
END;
$BODY$ LANGUAGE 'plpgsql';