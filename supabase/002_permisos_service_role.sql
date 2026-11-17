-- =====================================================================
-- 002_permisos_service_role.sql
-- Corrige "42501 permission denied for table documents" y endurece permisos.
--
-- Diagnóstico (consulta de solo lectura sobre information_schema.role_table_grants):
--   anon / authenticated -> REFERENCES, TRIGGER, TRUNCATE   (permisos de más)
--   service_role         -> REFERENCES, TRIGGER, TRUNCATE   (faltan SELECT/INSERT/UPDATE/DELETE)
--
-- Qué hace: (1) quita los permisos a los roles públicos y (2) le da a service_role,
-- la clave secreta que usa n8n en el servidor, lo mínimo para leer y escribir.
-- Riesgo: bajo (tabla vacía al momento de aplicarlo). Reversión al final.
-- =====================================================================

-- 1) Quitar permisos a los roles públicos (las claves anon y de usuarios no deben tocar esta tabla)
revoke all on table public.documents from anon, authenticated;
revoke execute on function public.match_documents(extensions.vector, integer, jsonb) from public, anon, authenticated;

-- 2) Dar permisos solo a service_role
grant usage on schema public to service_role;
grant usage on schema extensions to service_role;
grant select, insert, update, delete on table public.documents to service_role;
grant usage, select on sequence public.documents_id_seq to service_role;
grant execute on function public.match_documents(extensions.vector, integer, jsonb) to service_role;

-- 3) Recargar el esquema de la API
notify pgrst, 'reload schema';

-- 4) VERIFICACIÓN (solo lectura). Esperado: filas solo para postgres y service_role,
--    y service_role con DELETE, INSERT, SELECT, UPDATE entre sus permisos.
select grantee, string_agg(privilege_type, ', ' order by privilege_type) as permisos
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'documents'
group by grantee
order by grantee;

-- =====================================================================
-- REVERSIÓN (volver al estado anterior)
--   revoke select, insert, update, delete on table public.documents from service_role;
--   revoke usage, select on sequence public.documents_id_seq from service_role;
--   revoke execute on function public.match_documents(extensions.vector, integer, jsonb) from service_role;
--   grant references, trigger, truncate on table public.documents to anon, authenticated;
-- =====================================================================
