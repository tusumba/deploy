-- Повтор обновляет хеш, чтобы после смены SEED_PASSWORD входил новый пароль.
INSERT INTO identity.users (id, email, nickname, global_role, password_hash) VALUES
    ('5eed0000-0000-4000-8000-000000000101', 'user1@tusumba.test', 'anna_petrova', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000102', 'user2@tusumba.test', 'ivan_sidorov', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000103', 'moderator@tusumba.test', 'moderator', 'moderator', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000104', 'owner@tusumba.test', 'event_owner', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000105', 'admin@tusumba.test', 'event_admin', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000106', 'editor@tusumba.test', 'event_editor', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000107', 'scanner@tusumba.test', 'event_scanner', 'user', :'password_hash'),
    ('5eed0000-0000-4000-8000-000000000108', 'club-admin@tusumba.test', 'club_admin', 'user', :'password_hash')
ON CONFLICT (id) DO UPDATE SET password_hash = EXCLUDED.password_hash;

SELECT 'Пользователи: ' || count(*) FROM identity.users WHERE id::text LIKE '5eed0000-%';
