# deploy

Развёртывание Tusumba: Docker Compose, шлюз nginx и стенд.

**Ответственный:** Андрей Зверев (задача #18905).

## Что внутри

- `docker-compose.yml`: пять сервисов бэкенда, PostgreSQL 16 (отдельная схема на сервис, расширение `pg_trgm`), RabbitMQ, Redis, nginx;
- конфигурация nginx: TLS, маршрутизация `/v1/...` по сервисам, ограничение частоты запросов, раздача статики веб-клиента;
- пути `/internal` nginx не проксирует, контейнеры сервисов не публикуют порты на хост и работают в закрытой сети Compose;
- секреты (ключи платёжного провайдера, JWT, доступы к базам) передаются через переменные окружения, в репозиторий не попадают; примеры лежат в `.env.example`;
- тестовый стенд и боевой сервер.

## Запуск

Нужны Git и Docker с Compose v2.

1. Склонируйте репозитории сервисов рядом с `deploy`:

   ```bash
   ./scripts/clone.sh
   ```

   Получится такая раскладка:

   ```
   identity-service/  events-service/  ticketing-service/
   moderation-service/  notifications-service/  deploy/
   ```

   Уже склонированные репозитории скрипт пропускает. Чтобы клонировать по SSH, задайте `TUSUMBA_GIT_URL=git@github.com:tusumba`.

2. Создайте `.env` из примера и при необходимости поменяйте пароли:

   ```bash
   cp .env.example .env
   ```

3. Поднимите окружение:

   ```bash
   docker compose up -d --build --wait
   ```

   Команда завершится, когда все healthchecks станут зелёными. Состояние: `docker compose ps`.

Шлюз: http://localhost:8080 (порт задаёт `HTTP_PORT`). Проверка шлюза: `curl http://localhost:8080/health`.

Остановить: `docker compose down`. Удалить ещё и данные PostgreSQL, RabbitMQ и Redis: `docker compose down -v`.

### Что поднимается

| Сервис Compose | Что это |
|---|---|
| `postgres` | PostgreSQL 16, база `tusumba` |
| `rabbitmq` | RabbitMQ 4.1 |
| `redis` | Redis 7.4 |
| `identity`, `events`, `ticketing`, `moderation`, `notifications` | сервисы бэкенда, образ собирается из `../<имя>-service` |
| `<имя>-migrate` | `alembic upgrade head` перед стартом сервиса, после этого завершается |
| `nginx` | шлюз, единственный контейнер с портом на хосте |

Каждый сервис должен собираться по `Dockerfile` в корне своего репозитория, слушать порт 8000, отвечать на `GET /health` и выполнять миграции командой `alembic upgrade head`. Всё это уже есть в `service-template`.

### PostgreSQL

При первом запуске на пустом томе `postgres/init.sh`:

- ставит расширение `pg_trgm` в схему `public`;
- для каждого сервиса создаёт роль и схему с именем сервиса (`identity`, `events`, `ticketing`, `moderation`, `notifications`), владелец схемы — роль сервиса, `search_path` = `<схема>, public`.

Роль сервиса не видит чужие схемы и не пишет в `public`. Скрипт не запускается повторно, если том `postgres-data` уже есть: после изменения `init.sh` или паролей БД выполните `docker compose down -v`.

Порты PostgreSQL, RabbitMQ и Redis на хост не публикуются. Подключиться к базе: `docker compose exec postgres psql -U postgres -d tusumba`.

### Переменные окружения

Все переменные лежат в `.env.example`. Без обязательных `docker compose` не запустится и назовёт недостающую.

| Переменная | Что это |
|---|---|
| `HTTP_PORT` | порт шлюза на хосте, по умолчанию `8080` |
| `ENVIRONMENT`, `LOG_LEVEL` | передаются во все сервисы |
| `POSTGRES_PASSWORD` | пароль суперпользователя `postgres` |
| `<СЕРВИС>_DB_PASSWORD` | пароль роли сервиса в PostgreSQL; символы `@ : / ? # %` в нём не используйте, он подставляется в URL |
| `RABBITMQ_USER`, `RABBITMQ_PASSWORD` | учётная запись RabbitMQ |
| `REDIS_PASSWORD` | пароль Redis |

Сервисы получают `SERVICE_NAME`, `ENVIRONMENT`, `LOG_LEVEL`, `DATABASE_URL`, `RABBITMQ_URL` и `REDIS_URL`.

### Шлюз nginx

Конфигурация: `nginx/default.conf`. Шлюз проксирует `/v1/...` и `/webhooks/payments` в сервис-владелец пути, пробрасывает `X-Request-ID` клиента или создаёт новый. Пути `/internal` и всё, что не описано в маршрутах, возвращают 404.

| Путь | Сервис |
|---|---|
| `/v1/auth`, `/v1/users`, `/v1/friend-requests`, `/v1/me/friends`, `/v1/me/invitations`, `/v1/events/{id}/invitations` | `identity` |
| `/v1/events/{id}/ticket-settings`, `.../purchases`, `.../registration`, `.../participants`, `.../friends-going`, `.../stats/sales`, `/v1/purchases`, `/v1/tickets`, `/v1/me/tickets`, `/v1/me/registrations`, `/webhooks/payments` | `ticketing` |
| `/v1/applications`, `/v1/complaints`, `/v1/moderation`, `/v1/me/applications`, `/v1/me/complaints` | `moderation` |
| `/v1/me/notification-settings`, `/v1/me/devices` | `notifications` |
| остальное под `/v1/events`, `/v1/clubs`, `/v1/team-invitations` | `events` |

Новый внешний путь сервиса нужно добавить в `map $uri $backend` в `nginx/default.conf`, иначе шлюз вернёт 404.

## Документация

Wiki проекта: https://ai.nsu.ru/projects/tusumba/wiki/Архитектура. Задачи ведутся в Redmine: https://ai.nsu.ru/projects/tusumba. Issues и Wiki GitHub выключены.

## Правила работы

Ветки, коммиты, pull request и code review описаны в [CONTRIBUTING.md](https://github.com/tusumba/.github/blob/main/CONTRIBUTING.md). Коротко:

- ветка называется `feature/<номер задачи Redmine>-<пара слов>`, например `feature/18901-login`;
- номер задачи указывается в каждом коммите и в названии PR;
- в `main` изменения попадают только через PR с одним одобрением и зелёным CI, прямой push и force push запрещены.
