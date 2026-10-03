// Conexión con Supabase. La clave "publishable" está pensada para ir en el frontend:
// lo que protege los datos son las reglas de acceso (Row Level Security) de supabase/schema.sql.
window.EF_CONFIG = {
  supabaseUrl: 'https://economiafamiliar.hernanmerlino2.workers.dev/',
    //'https://toqzpgwgpviqvjdegaii.supabase.co',
  supabaseKey: 'sb_publishable_LPrlshW8b8CjDYrUVXhSow_UBTY6tz_'
};
