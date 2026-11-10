# deploy

Развёртывание Tusumba: Docker Compose, шлюз nginx и стенд.

**Ответственный:** Андрей Зверев (задача #18905).

## Что внутри

- `docker-compose.yml`: пять сервисов бэкенда, PostgreSQL 16 (отдельная схема на сервис, расширение `pg_trgm`), RabbitMQ, Redis, nginx;
- конфигурация nginx: TLS, маршрутизация `/v1/...` по сервисам, ограничение частоты запросов, раздача статики веб-клиента;
- пути `/internal` nginx не проксирует, контейнеры сервисов не публикуют порты на хост и работают в закрытой сети Compose;
- секреты (ключи платёжного провайдера, JWT, доступы к базам) передаются через переменные окружения, в репозиторий не попадают; примеры лежат в `.env.example`;
- мониторинг доступности (Gatus) и логи всех контейнеров в браузере (Dozzle);
- тестовый стенд и боевой сервер.

## Запуск

<<<<<<< Updated upstream
Описание появится после готовности Compose-файла (#18905).
=======
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

   Затем создайте ключи JWT для стенда:

   ```bash
   ./scripts/dev-keys.sh
   ```

   Скрипт создаёт пару RSA-ключей в `secrets/` (каталог не попадает в git) и записывает публичный ключ в `JWT_PUBLIC_KEY` в `.env`. Существующий `secrets/jwt-private.pem` не перезаписывается, повторный запуск только обновит строку в `.env`. Закрытым ключом `secrets/jwt-private.pem` Identity подписывает токены.

3. Поднимите окружение:

   ```bash
   docker compose up -d --build --wait
   ```

   Команда завершится, когда все healthchecks станут зелёными. Состояние: `docker compose ps`.

Шлюз: http://localhost:8080 (порт задаёт `HTTP_PORT`). Проверка шлюза: `curl http://localhost:8080/health`.

Мониторинг: http://localhost:8081, логи: http://localhost:8081/logs/. Логин и пароль — `OPS_USER` и `OPS_PASSWORD` из `.env`.

Остановить: `docker compose down`. Удалить ещё и данные PostgreSQL, RabbitMQ и Redis: `docker compose down -v`.

### Что поднимается

| Сервис Compose | Что это |
|---|---|
| `postgres` | PostgreSQL 16, база `tusumba` |
| `rabbitmq` | RabbitMQ 4.1 |
| `redis` | Redis 7.4 |
| `identity`, `events`, `ticketing`, `moderation`, `notifications` | сервисы бэкенда, образ собирается из `../<имя>-service` |
| `<имя>-migrate` | `alembic upgrade head` перед стартом сервиса, после этого завершается |
| `nginx` | шлюз API и вход в мониторинг и логи, единственный контейнер с портами на хосте |
| `gatus` | мониторинг доступности |
| `dozzle` | просмотр логов контейнеров |

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
| `OPS_PORT` | порт мониторинга и логов на хосте, по умолчанию `8081` |
| `OPS_USER`, `OPS_PASSWORD` | логин и пароль для мониторинга и логов; в `OPS_USER` не должно быть `:` |
| `JWT_PUBLIC_KEY` | публичный ключ Identity в PEM одной строкой, переводы строк записаны как `\n`, значение в одинарных кавычках; заполняет `scripts/dev-keys.sh` |
| `SERVICE_TOKEN` | общий токен для вызовов `/internal` между сервисами (заголовок `X-Service-Token`); на общем стенде замените значение из примера на случайную строку |

Сервисы получают `SERVICE_NAME`, `ENVIRONMENT`, `LOG_LEVEL`, `DATABASE_URL`, `RABBITMQ_URL`, `REDIS_URL`, `JWT_PUBLIC_KEY` и `SERVICE_TOKEN`. Последние два читает `tusumba-common`: без них сервис стартует, но запросы с токеном и вызовы `/internal` отвечают 500, поэтому `docker compose` без них не запускается.

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
>>>>>>> Stashed changes

## Мониторинг и логи

Мониторинг и логи открываются на порту `OPS_PORT` через nginx с паролем (HTTP Basic). nginx при старте собирает файл паролей из `OPS_USER` и `OPS_PASSWORD` скриптом `nginx/ops-htpasswd.sh`. Пароль меняется правкой `.env` и `docker compose up -d nginx`.

nginx не ждёт готовности сервисов: если сервис не поднялся, мониторинг и логи всё равно открываются, а запросы к этому сервису получают 502.

На стенде без TLS пароль передаётся открытым текстом. Ставьте длинный пароль и не открывайте порт мониторинга в интернет, пока на шлюзе нет TLS.

### Healthchecks

У каждого долгоживущего контейнера есть healthcheck, состояние видно в `docker compose ps`:

| Контейнер | Проверка |
|---|---|
| сервисы бэкенда | `GET /health` на порту 8000 |
| `postgres` | `pg_isready` по TCP |
| `rabbitmq` | `rabbitmq-diagnostics ping` |
| `redis` | `redis-cli ping` с паролем |
| `nginx` | `GET /health` шлюза |
| `dozzle` | `dozzle healthcheck` |

У `gatus` healthcheck нет: в образе нет ни shell, ни утилит, только сам Gatus. Если он упал, страница мониторинга отвечает 502, а его контейнер виден в Dozzle.

Docker сам не перезапускает контейнер, который стал `unhealthy`. Такой сервис виден красным в мониторинге; перезапустить: `docker compose restart <сервис>`. Упавший процесс Docker перезапускает сам (`restart: unless-stopped`).

### Мониторинг: Gatus

http://localhost:8081. Конфигурация: `gatus/config.yaml`. Каждые 15 секунд Gatus проверяет изнутри сети Compose:

- сервисы бэкенда: `GET /health` отвечает 200 с `{"status": "ok"}` быстрее 1 секунды;
- шлюз nginx: `GET /health`;
- PostgreSQL, RabbitMQ, Redis: порт принимает TCP-подключения.

Остановленный, упавший или зависший сервис через 15 секунд становится красным, в карточке видна ошибка. История проверок хранится в томе `gatus-data` и переживает перезапуск.

Новый сервис добавляется отдельным пунктом в `endpoints` в `gatus/config.yaml`.

### Логи: Dozzle

http://localhost:8081/logs/. Dozzle показывает в реальном времени логи всех контейнеров стенда, с поиском и фильтром по уровню. JSON-логи сервисов разбираются по полям, поиск работает по тексту, в том числе по `request_id`. Контейнеры других проектов на этом хосте Dozzle не показывает.

Dozzle читает логи через Docker API, поэтому к нему подключён `/var/run/docker.sock` только на чтение. Действия с контейнерами и shell в Dozzle выключены.

Логи хранит Docker: у каждого контейнера до 5 файлов по 10 МБ, старые удаляются. Из терминала: `docker compose logs -f <сервис>`.

## Документация

Wiki проекта: https://ai.nsu.ru/projects/tusumba/wiki/Архитектура. Задачи ведутся в Redmine: https://ai.nsu.ru/projects/tusumba. Issues и Wiki GitHub выключены.

## Правила работы

Ветки, коммиты, pull request и code review описаны в [CONTRIBUTING.md](https://github.com/tusumba/.github/blob/main/CONTRIBUTING.md). Коротко:

- ветка называется `feature/<номер задачи Redmine>-<пара слов>`, например `feature/18901-login`;
- номер задачи указывается в каждом коммите и в названии PR;
- в `main` изменения попадают только через PR с одним одобрением и зелёным CI, прямой push и force push запрещены.
