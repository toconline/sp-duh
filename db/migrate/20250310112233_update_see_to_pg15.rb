class UpdateSeeToPg15 < ActiveRecord::Migration
  def up
    execute <<-'SQL'
      DROP FUNCTION IF EXISTS public.see(text, text, text, text, text, bool);

      CREATE OR REPLACE FUNCTION see (
        a_module          text,
        a_version         text,
        a_query_map       text,
        a_calc_parameters text,
        a_log             text default null,
        a_debug           boolean default false
      ) RETURNS SETOF see_record AS '$libdir/pg-see.so', 'see' LANGUAGE C STRICT;
    SQL
  end

  def down
    execute <<-'SQL'
      DROP FUNCTION IF EXISTS public.see(text, text, text, text, text, bool);

      CREATE OR REPLACE FUNCTION see (
      a_module          text,
      a_version         text,
      a_query_map       text,
      a_calc_parameters text,
      a_log             text default null,
      a_debug           boolean default false
      ) RETURNS see_record AS '$libdir/pg-see.so', 'see' LANGUAGE C STRICT;
    SQL
  end
end
