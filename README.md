# deploy

Развёртывание Tusumba: Docker Compose, шлюз nginx и стенд.

**Ответственный:** Андрей Зверев (задача #18905).

## Что внутри

- `docker-compose.yml`: пять сервисов бэкенда, PostgreSQL 16 (отдельная схема на сервис, расширение `pg_trgm`), RabbitMQ, Redis, nginx;
- HTTPS на сервере через Caddy с сертификатом Let's Encrypt (`docker-compose.prod.yml`) и автодеплой из `main` (`scripts/update.sh`);
- конфигурация nginx: маршрутизация `/v1/...` по сервисам, ограничение частоты запросов, раздача статики веб-клиента;
- пути `/internal` nginx не проксирует, контейнеры сервисов не публикуют порты на хост и работают в закрытой сети Compose;
- секреты (ключи платёжного провайдера, JWT, доступы к базам) передаются через переменные окружения, в репозиторий не попадают; примеры лежат в `.env.example`;
- мониторинг доступности (Gatus) и логи всех контейнеров в браузере (Dozzle);
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

   Затем создайте ключи JWT для стенда:

   ```bash
   ./scripts/dev-keys.sh
   ```

   Скрипт создаёт пару RSA-ключей в `secrets/` (каталог не попадает в git) и записывает ключи в `.env`: публичный в `JWT_PUBLIC_KEY`, закрытый в `JWT_PRIVATE_KEY`. Существующий `secrets/jwt-private.pem` не перезаписывается, повторный запуск только обновит строки в `.env`. Закрытым ключом Identity подписывает токены, остальные сервисы проверяют их публичным.

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
| `JWT_PRIVATE_KEY` | закрытый ключ Identity в том же виде, передаётся только в `identity`; заполняет `scripts/dev-keys.sh` |
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

## Тестовые данные

`scripts/seed.sh` заполняет базу тестовыми пользователями, секциями и мероприятиями для разработки Android и веба.

Перед первым запуском добавьте в `.env` пароль тестовых пользователей, от 8 до 128 символов. В `.env.example` его нет: без него скрипт завершится с ошибкой.

```
SEED_PASSWORD=<пароль>
```

Запускайте скрипт после `docker compose up -d --build --wait`, когда миграции прошли и `identity` работает:

```bash
./scripts/seed.sh
```

На стенде:

```bash
cd /opt/tusumba/deploy
sudo -u tusumba ./scripts/seed.sh
```

Повторный запуск безопасен: дублей не будет, а даты мероприятий пересчитаются от текущего дня, чтобы мероприятия не пропадали из каталога. Пароль пользователей тоже обновится, если `SEED_PASSWORD` изменился. Убрать тестовые данные можно только вместе со всей базой: `docker compose down -v`, затем снова `up` и, если нужно, `seed.sh`.

### Пользователи

Войти можно по почте или нику (`POST /v1/auth/login`). Пароль у всех — `SEED_PASSWORD` из `.env`.

| Почта | Ник | Роль |
|---|---|---|
| `user1@tusumba.test` | `anna_petrova` | обычный пользователь |
| `user2@tusumba.test` | `ivan_sidorov` | обычный пользователь |
| `moderator@tusumba.test` | `moderator` | модератор (`global_role = moderator`) |
| `owner@tusumba.test` | `event_owner` | владелец всех мероприятий от пользователя |
| `admin@tusumba.test` | `event_admin` | администратор «Посвящения в студенты ФИТ» |
| `editor@tusumba.test` | `event_editor` | редактор «Посвящения в студенты ФИТ» |
| `scanner@tusumba.test` | `event_scanner` | контролёр «Посвящения в студенты ФИТ» |
| `club-admin@tusumba.test` | `club_admin` | администратор всех секций и владелец мероприятий от секций |

### Секции и мероприятия

- 5 секций: 4 опубликованы и видны в `GET /v1/clubs`, «Клуб любителей аниме» заблокирован, его нет в каталоге, а `GET /v1/clubs/{id}` отвечает 404;
- 7 мероприятий в `GET /v1/events`: через 3-45 дней от дня запуска, бесплатные и платные (200, 300, 500 и 1500 ₽), со статусами `confirmed` и `not_confirmed`; два из них от секций (турнир клуба настольных игр и концерт хора), остальные от пользователя `event_owner`.

Фото у секций и мероприятий нет, заявок, билетов и друзей скрипт не создаёт.

## Мониторинг и логи

Мониторинг и логи открываются на порту `OPS_PORT` через nginx с паролем (HTTP Basic). nginx при старте собирает файл паролей из `OPS_USER` и `OPS_PASSWORD` скриптом `nginx/ops-htpasswd.sh`. Пароль меняется правкой `.env` и `docker compose up -d nginx`.

nginx не ждёт готовности сервисов: если сервис не поднялся, мониторинг и логи всё равно открываются, а запросы к этому сервису получают 502.

Локально мониторинг работает по HTTP. На сервере он доступен только по HTTPS на порту 8443, порт `OPS_PORT` наружу не публикуется (см. «Сервер стенда»).

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

## Сервер стенда

Общий стенд работает на Linux-сервере с тем же `docker-compose.yml` и дополнением `docker-compose.prod.yml`:

- перед шлюзом nginx стоит Caddy: принимает HTTPS на 443, сам получает и продлевает сертификаты Let's Encrypt для `DOMAIN` и `SERVICE_DOMAINS`, с 80 перенаправляет на HTTPS;
- мониторинг и логи открываются по `https://<DOMAIN>:8443` (логи на `/logs/`), с тем же паролем `OPS_USER`/`OPS_PASSWORD`;
- nginx не публикует порты на хост, снаружи доступен только Caddy: порты 80, 443 и 8443.

Адреса стенда:

| Адрес | Что открывает |
|---|---|
| https://testweb.tusumba.ru | шлюз: весь API `/v1/...` по маршрутам из `nginx/default.conf`; этот адрес — `BASE_URL` для Android и веба |
| https://id.tusumba.ru, https://events.tusumba.ru, https://ticketing.tusumba.ru, https://moderation.tusumba.ru, https://notifications.tusumba.ru | напрямую свой сервис: `/v1/...`, `/health`, Swagger на `/docs` |
| https://testweb.tusumba.ru:8443 | мониторинг, логи на `/logs/`, с паролем |

Домен сервиса nginx узнаёт по первой части имени (`id.` — `identity`, остальные совпадают с именем сервиса), список — `map $service_host` в `nginx/default.conf`. `/internal` закрыт и на шлюзе, и на доменах сервисов.

nginx передаёт сервисам адрес клиента в `X-Real-IP` и `X-Forwarded-For` и исходную схему в `X-Forwarded-Proto`. Адресу из `X-Forwarded-For` nginx доверяет только от частных сетей, то есть от Caddy внутри сети Compose.

### Автодеплой

Каждые 2 минуты systemd-таймер запускает `scripts/update.sh`. Скрипт:

1. клонирует недостающие репозитории сервисов (`scripts/clone.sh`);
2. подтягивает `main` в `deploy` и во всех репозиториях сервисов (только fast-forward);
3. если коммиты не изменились с последнего успешного деплоя, ничего не делает;
4. иначе выполняет `docker compose up -d --build --wait --remove-orphans`, записывает коммиты в `.deployed` и удаляет неиспользуемые образы.

Сервис, в репозитории которого ещё нет `Dockerfile`, скрипт пропускает вместе с его миграциями и пишет об этом в журнал. Запросы к такому сервису получают 502, в мониторинге он красный. Как только `Dockerfile` появится в `main`, следующий запуск таймера поднимет сервис.

Пересоздаются только контейнеры, у которых изменился образ или конфигурация: коммит в `events-service` перезапускает только `events` и его миграции. Конфиги nginx, Gatus и Caddy подключены файлами, и Docker не видит их изменений сам, поэтому `update.sh` ставит на контейнер метку с хешем каталога (`nginx/`, `gatus/`, `caddy/`) из git: изменился каталог — контейнер пересоздаётся.

Если сборка или healthcheck не прошли, `.deployed` не обновляется: работающие контейнеры продолжают работать, а следующий запуск таймера пробует снова. Ошибки видны в журнале:

```bash
journalctl -u tusumba-update -n 100
```

Обновить стенд сразу, не дожидаясь таймера: `sudo systemctl start tusumba-update`.

### Настройка сервера

Нужны Linux-сервер с Docker Engine и Compose не ниже 2.24, домены и открытые порты 80, 443 и 8443. На Oracle Cloud порт открывается в двух местах: в firewalld на сервере (`sudo firewall-cmd --permanent --add-port=8443/tcp && sudo firewall-cmd --reload`) и в Security List подсети в консоли Oracle Cloud.

1. Направьте A-записи доменов на IP сервера.

2. Создайте пользователя для стенда и склонируйте репозитории в `/opt/tusumba`:

   ```bash
   sudo useradd --system --create-home --groups docker tusumba
   sudo mkdir -p /opt/tusumba && sudo chown tusumba: /opt/tusumba
   sudo -u tusumba git clone https://github.com/tusumba/deploy.git /opt/tusumba/deploy
   cd /opt/tusumba/deploy
   sudo -u tusumba ./scripts/clone.sh
   ```

3. Создайте `.env` и ключи JWT:

   ```bash
   sudo -u tusumba cp .env.example .env
   sudo -u tusumba ./scripts/dev-keys.sh
   ```

   В `.env` замените все пароли и `SERVICE_TOKEN` на случайные строки (`openssl rand -hex 24`) и добавьте:

   ```
   COMPOSE_FILE=docker-compose.yml:docker-compose.prod.yml
   DOMAIN=testweb.tusumba.ru
   SERVICE_DOMAINS=id.tusumba.ru events.tusumba.ru ticketing.tusumba.ru moderation.tusumba.ru notifications.tusumba.ru
   ```

   `COMPOSE_FILE` подключает `docker-compose.prod.yml` ко всем командам `docker compose` в этом каталоге. `.env` и `secrets/` должны быть доступны только пользователю `tusumba` (`chmod 600`).

4. Поднимите стенд первый раз:

   ```bash
   sudo -u tusumba ./scripts/update.sh
   ```

   Проверка: `curl https://<DOMAIN>/health` отвечает `ok`.

5. Включите автодеплой:

   ```bash
   sudo cp server/tusumba-update.service server/tusumba-update.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now tusumba-update.timer
   ```

Пути `/opt/tusumba/deploy` и пользователь `tusumba` прописаны в `server/tusumba-update.service`. Если стенд стоит в другом месте, поправьте их там.

Руками в каталогах на сервере ничего не меняйте и не переключайте ветки: `update.sh` делает только fast-forward `main` и остановится с ошибкой, если в репозитории есть свои коммиты.

## Документация

Wiki проекта: https://ai.nsu.ru/projects/tusumba/wiki/Архитектура. Задачи ведутся в Redmine: https://ai.nsu.ru/projects/tusumba. Issues и Wiki GitHub выключены.

## Правила работы

Ветки, коммиты, pull request и code review описаны в [CONTRIBUTING.md](https://github.com/tusumba/.github/blob/main/CONTRIBUTING.md). Коротко:

- ветка называется `feature/<номер задачи Redmine>-<пара слов>`, например `feature/18901-login`;
- номер задачи указывается в каждом коммите и в названии PR;
- в `main` изменения попадают только через PR с одним одобрением и зелёным CI, прямой push и force push запрещены.
