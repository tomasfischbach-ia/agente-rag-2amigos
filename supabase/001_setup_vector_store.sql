-- =====================================================================
-- 001_setup_vector_store.sql
-- Base vectorial para el agente RAG de 2 Amigos Aberturas (Supabase + pgvector)
-- Modelo de embeddings: Google gemini-embedding-001 -> 3072 dimensiones
-- Se puede correr más de una vez sin romper nada (idempotente).
-- =====================================================================

-- 1) Extensión pgvector (en el esquema "extensions", como recomienda Supabase)
create extension if not exists vector with schema extensions;

-- 2) Tabla que usa el nodo Supabase Vector Store de n8n.
--    El nodo solo escribe estas columnas: content, metadata y embedding.
create table if not exists public.documents (
  id         bigserial primary key,
  content    text,
  metadata   jsonb,
  embedding  extensions.vector(3072),
  created_at timestamptz not null default now()
);

-- 3) Seguridad: RLS activado y sin políticas.
--    La clave pública (anon) no puede leer ni escribir; n8n usa la service_role, que saltea RLS.
alter table public.documents enable row level security;

-- 4) Función de búsqueda por similitud que llama n8n (Query Name = match_documents)
create or replace function public.match_documents (
  query_embedding extensions.vector(3072),
  match_count int default null,
  filter jsonb default '{}'
) returns table (id bigint, content text, metadata jsonb, similarity float)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select id, content, metadata,
         1 - (documents.embedding <=> query_embedding) as similarity
  from public.documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- 5) Recargar el esquema de la API para que n8n vea la tabla y la función enseguida
notify pgrst, 'reload schema';

-- Nota: no se crea índice. pgvector permite índices HNSW/IVFFlat hasta 2000 dimensiones
-- con el tipo vector, y con unos cientos de fragmentos la búsqueda completa es rápida.

-- =====================================================================
-- CONSULTAS DE VERIFICACIÓN (solo lectura). Correlas DESPUÉS de la ingesta.
-- =====================================================================
-- ¿Cuántos fragmentos hay por página?
--   select metadata->>'source' as fuente, count(*) as fragmentos
--   from public.documents group by 1 order by 1;
--
-- ¿La dimensión guardada es la esperada? (debe dar 3072)
--   select vector_dims(embedding) from public.documents limit 1;
--
-- =====================================================================
-- REINDEXAR DESDE CERO (DESTRUCTIVO: borra todos los fragmentos).
-- Usar solo si querés volver a correr la ingesta completa sin duplicados.
--   truncate table public.documents;
-- =====================================================================
