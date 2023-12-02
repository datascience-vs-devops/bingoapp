# Yandex DevOps BingoApp CTF Competition
### _Описание и техническое задание находится по адресу:_
https://disk.yandex.ru/i/lHRYD7kWCnQTxg


В процессе выполнения удалось решить все основные поставленные задачи.
На задачи со звёздочками не хватило времени в связи с болезнью в последние 4 дня конкурса, поэтому данный отчёт про ручное развёртывание, а автоматическое, практически работающее (если чуть подготовить окружение), но ни разу не проверенное Петей, в самом конце кратко опишу.

Далее идёт описание шагов решения

## Запуск приложения

При запуске приложение выводит сообщение "Hello world", что сразу радует :)
Пробую ключ --help (-h), он срабатывает и выводит дополнительную информацию:

```sh
$ ./bingo -h

Usage:
   [flags]
   [command]

Available Commands:
  completion           Generate the autocompletion script for the specified shell
  help                 Help about any command
  prepare_db           prepare_db
  print_current_config print_current_config
  print_default_config print_default_config
  run_server           run_server
  version              version
  
Flags:
  -h, --help   help for this command

Use " [command] --help" for more information about a command.
```
Становится понятно, что конечная цель, это запустить приложение с ключом **run_server**.
Пробую напечатать текущий конфиг, приложение "крашится".

```
$ ./bingo print_current_config

panic: failed to read config data
        /home/vgbadaev/go/pkg/mod/github.com/spf13/cobra@v1.7.0/command.go:992
        /build/cmd/bingo/main.go:22 +0x85
```

Становится понятно, что приложение написано на **Go**, его автор ;), а также то, что будут нужны инструменты отладки.
Запускаю через strace:
```
$ strace ./bingo print_current_config
```
И нахожу в выводе обращение к несуществующему файлу:
```
openat(AT_FDCWD, "/opt/bingo/config.yaml", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
```
Создаю его, а понять то, как он должен выглядеть помогает команда:
```
$ ./bingo print_default_config

student_email: test@example.com
postgres_cluster:
  hosts:
  - address: localhost
    port: 5432
  user: postgres
  password: postgres
  db_name: postgres
  ssl_mode: disable
  use_closest_node: false
```
А значит пришло время для работы с базой данных.
В конфиге есть интересные намёки на необходимость кластера. Но буду использовать один сервер БД, потому что делаю всё локально. Поэтому меняю только email, user, password и db_name.

```
CREATE DATABASE bingodb;
CREATE USER bingo WITH PASSWORD 'bingopass';
GRANT ALL PRIVILEGES ON DATABASE bingodb TO bingo;
```

Пробую запустить приложение с ключом prepare_db и пошло наполнение базы данными!
Отлично, большой шаг к запуску сделан.

Ждём какое-то время, по окончании смотрим, что за данные:

```
bingo=# \dt
             List of relations
 Schema |       Name        | Type  | Owner
--------+-------------------+-------+-------
 public | customers         | table | bingo
 public | movies            | table | bingo
 public | schema_migrations | table | bingo
 public | sessions          | table | bingo
(4 rows)

bingo=# select count(*) from sessions;
  count
---------
 5000000
(1 row)

bingo=# \d sessions;
                                         Table "public.sessions"
   Column    |            Type             | Collation | Nullable |               Default
-------------+-----------------------------+-----------+----------+--------------------------------------
 id          | bigint                      |           | not null | nextval('sessions_id_seq'::regclass)
 start_time  | timestamp without time zone |           | not null |
 customer_id | integer                     |           | not null |
 movie_id    | integer                     |           | not null |
```
В самой большой таблице 5000000 записей, а **индексов ни в одной таблице нет!** Запоминаем это момент.

Теперь пробую запустить **run_server**
Приложение опять падает. Нахожу проблемное место тем же самым методом при помощи strace:

```
$ strace ./bingo run_server

openat(AT_FDCWD, "/opt/bongo/logs/a516f07394/main.log", O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC, 0666) = -1 ENOENT (No such file or directory)
```

Так же, как и конфиг, захардкожен путь, куда пишется лог - создаю директории и даю нужные права.

```
mkdir -p /opt/bongo/logs/a516f07394/
chown -R bingo:bingo /opt/bongo
```

Снова запускаю и вау! Какой-то секретный код **yoohoo_server_launched**

```
$ ./bingo run_server

My congratulations.
You were able to start the server.
Here's a secret code that confirms that you did it.
--------------------------------------------------
code:         yoohoo_server_launched
--------------------------------------------------
```
В тот момент на долгий запуск приложения внимание обратил, но радость от того, что так быстро разобрался с запуском, была выше) Вернулся к этому моменту чуть позже.

А пока проверю на каком порту запустилось приложение.
```
$ sudo netstat -lntup

tcp6       0      0 :::3901                 :::*                    LISTEN      15072/./bingo
```
tcp6, хм-хм, необычно, но не смертельно)

Дополнительно обращаю внимание на то, что лог в формате json и то, как быстро он растёт, за счёт сохранения всего env в каждой записи. На тот момент не найдя ничего интересного в лог файле, принимаю кардинальное решение:
```
$ ls -la
lrwxrwxrwx 1 bingo bingo 9 ноя 22 18:03 main.log -> /dev/null
```

На этом моменте считаю, что самый интересный и неожиданный этап конкурса завершён - приложение запущено.

## Достижение SLA по RPS

Первые же тесты показали, что приложение не умеет (не хочет :) отдавать  больше 100 RPS.
```
$ ab -n 1000 -c 1 http://localhost:3901/ping
Requests per second:    100.37 [#/sec] (mean)
  95%     51
  98%     51
  99%     51
 100%     51 (longest request)

$ ab -n 1000 -c 4 http://localhost:3901/ping
Requests per second:    100.40 [#/sec] (mean)
  95%     52
  98%     52
  99%     77
 100%    102 (longest request)
```
Тестирую на эндпоинте healthcheck'а, потому что по логике, он должен работать быстрее всего.
Увеличение concurrency ничего не даёт, а значит приложение залочено на эти показатели и становится понятно, что достижение 120 RPS возможно, только при наличии двух нод. А значит пришло время подумать над архитектурой.
Так же обращаю внимание на ms ответов - даже под нагрузкой время ответа растёт не сильно - единичные просадки.

Запросил доступы до Yandex Cloud, пока не понятно, какие там ресурсы будут, но кажется неплохим решением поставить на фронт nginx, которым проксировать входящие запросы на ноды bingoapp, а те в свою очередь будут ходить в ещё более глубокий тыл к серверу(ам) БД.

В итоге под каждый узел решено было выделить отдельную виртуальную машину.
Решил, что сначала нужно добиться выполнения основных требований, а уже потом буду оптимизировать.
Использовались минимальные конфигурации 2 ядра/2 гига/HDD, на БД - SSD.

В **nginx.conf** добавил минимальные изменения (но в репозитории лежит более сложный конфиг для http/3):
``` 
    proxy_cache_path  /var/nginx/cache levels=1:2 keys_zone=STATIC:1m inactive=1m max_size=10m;   
    upstream bingoapp{
       server 10.100.0.5:3901;
       server 10.100.0.6:3901;
    }

    server {
        listen       80;
        listen       443 ssl http2;
        server_name  _;

        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
    
        location / {
            proxy_pass http://bingoapp;
        }

        location /long_dummy {
            proxy_cache            STATIC;
            proxy_cache_valid      200  1m;
            proxy_cache_use_stale  error timeout invalid_header updating
                                   http_500 http_502 http_503 http_504;
            proxy_pass http://bingoapp;
        }
    }
```

Для Postgres'а столько памяти под буферы даже много оказалось.
А 10ms, чтобы все запросы логировать (ждал Петю)). Одно дело свои тесты, но понятно было, что Петя умеет лучше)
```
shared_buffers = 1024MB
log_min_duration_sample = 10ms 
```
Для тестирования по эндпоинтам c {id} решил использовать **siege** - он позволяет гонять бенчмарки по многим урлам, что правильнее в плане нагрузки БД (помним, что индексов пока нет).

на виртуалках только python2, f-strings ещё нет.
``` python
from random import randint

#host = '158.160.118.139'
host = 'localhost'

for i in range(1,50001):
    print('http://%s/api/movie/%s' % (host, randint(1,29019)))
    print('http://%s/api/customer/%s' % (host, randint(1,500000)))
    print('http://%s/api/session/%s' % (host, randint(1,5000000)))
```

Вывод писал в лог, чтобы потом отсортировать время самых медленных запросов.
```
$ siege -r 150000 -c 4 -f warm_cache > siege.out
$ cat siege.out | awk '{print $3}'| sort -nr| uniq -c| head -20
```
concurency=4, потому что приложение создавало два коннекта в базу. Итого две ноды, значит будем бенчить в 4 потока.
Но впоследствии отказался от 4-х - слишком много ошибок "Too many requests" в логах самого приложения.

Но это не касалось основного эндпоинта, по которому, как я понял, проверялся RPS - **/db_dummy**
Он делал простой, но немного медленный, запрос - **SELECT pg_sleep(0.1)**
Кстати именно увидев этот запрос, я уменьшил в конфиге базы порог логирования до 10мс, до этого был 100мс - хотелось видеть вообще всё, что запрашивает приложение.

Так же в начале ловил запросы непосредственно в процессе тестов:
```
SELECT pid, age(clock_timestamp(), query_start), usename, query FROM pg_stat_activity ORDER BY query_start desc;
```
Ну и уже на облаке не стал девнуллить логи, а начал наблюдать за происходящим и с приложением.
```
grep -f "request completed" main.log | jq -r '[.timestamp,.url_path,.event_duration]|@csv'
```

В итоге, как и планировал изначально, добавил индексы на таблицы, что кардинально уменьшило время ответа.
```
CREATE INDEX movieid_idx ON movies (id);
CREATE INDEX customerid_idx ON customers (id);
CREATE INDEX sessionid_idx ON sessions (id);
```
Позднее пробовал добавлять и другие индексы, но ситуацию они практически не меняли.

После проверки всех эндпоинтов убедился что все GET запросы удовлетворяют SLA, когда две ноды приложения работают :)
И об этом в следующем разделе.

Угадать с POST /operation какие-то рабочие id было невозможно, как позже показал Петя. Рандомные попостил curloм, ответ приходил один и тот же. Ну так и оставил и больше не пришлось этого касаться.

POST и DELETE на добавление/удаление сессии убедился, что работают.

## Отказоусточивость
Ну и подошли к самому важному пункту.
К этому моменту уже давно выяснилось, что приложение живёт в среднем 22-25 минут, даже без какой-либо нагрузки, а потом начинает умирать с разными сценариями.

Сначала запуск осуществлялся простым **while true** по кругу. И в сценариях, когда приложение тихо умирало, ну или писало We all die, это решение работало. Но самый редкий и самый подлый :) сценарий, когда приложение начинало выедать всю память, заставило пересмотреть всю концепцию.

Вот конечный .service файл для systemd
```
[Unit]
Description=BingoApp
Requires=network.target

[Service]
Type=simple
User=bingo
Group=bingo
WorkingDirectory=/opt/bingo
OOMScoreAdjust=1000
ExecStartPre=/opt/bingo/savelog.sh
ExecStart=/opt/bingo/bingo run_server
KillMode=mixed
TimeoutStartSec=10
TimeoutStopSec=3
LimitNOFILE=100
MemoryHigh=25M
MemoryMax=30M
#WatchdogSec=1200
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
```

Что сразу заметил - резко сократился размер лог-файла, так как уменьшились переменные окружения, поэтому решил логи не удалять после каждого перезапуска, как делал раньше, а сохранять, чтобы когда-нибудь потом :) передавать прометею. Плюс таким образом удобно отслеживать времена рестартов.

/opt/bingo/savelog.sh
```
#!/bin/sh

dt = $(date "+%Y-%m-%dT%H-%M-%S"

/usr/bin/mv /opt/bongo/logs/a516f07394/main.log  /opt/bongo/logs/a516f07394/main.log.$dt
gzip /opt/bongo/logs/a516f07394/main.log.$dt &
```

На ходу пробовал разбирать без "|" - написал на pythone небольшой парсер, чтобы выделить только нужные записи необходимые для статистики(msg = request complete), но он работал заметно медленнее, чем **tail -f| jq.**

Открыл утилиту jq - крайне полезная. Типовые запросы из history/
```
cat main.log | jq .msg | sort | uniq -c # все типы сообщений
tail -f main.log | grep "error" | jq -r "[.timestamp, .msg]|@csv" # ошибки
cat main.log | grep "Prepare app." | jq -r "[.timestamp, .msg]|@csv" # ищу старты
```


Теперь по самому сервис-файлу.
**OOMScoreAdjust=1000**
**MemoryHigh=25M**
**MemoryMax=30M**
не сильно помогли обрабатывать самый неудобный сценарий, когда утекала память - сервер не рестартился, но и не работал как надо.

**Restart=always**
**RestartSec=1s**
решали остальные сценарии.

Ну и постоянно висящие в tmux'е atop'ы htop'ы и прочие *stat для каждой ноды. Запускаю бенч и переключаюсь по вкладкам - смотрю что происходит, пытаюсь найти узкие места. Поначалу, пока ещё непонятно было, как ведёт себя приложение, действительно, только глазами наблюдаешь.
Писал ночной лог atop'ом, чтобы отловить самый неприятный сценарий, но выбрал частоту в 30 секунд, слишком много.
Сделал вывод, что для хороших приложений раз в минуту может и норм, а для таких случаев лучше делать слепок почаще.

Довольно хорошо себя зарекомендовал **WatchdogSec=1200**.
**wrk** с ним проработал всю ночь с неплохими показателями на эндпоинте /ping (а зачем что-то другое, если тестировалась именно доступность сервиса).
```
  Latency Distribution
     50%   10.93ms
     75%   26.37ms
     90%   41.47ms
     99%   56.38ms
  6425385 requests in 550.88m, 1.00GB read
  Non-2xx or 3xx responses: 1435
Requests/sec:    194.40
Transfer/sec:     31.70KB
```

На этом моменте появился Петя и сервис был первый раз отправлен на тестирование.

Если не учитывать оплошности со временем (изначально все виртуалки, кроме nginx планировались без публичных ip адресов, но оказалось, что и исходящего инета тоже нет, поэтому такими остались только ноды с бинго. Ну и на них в связи с этим не было настроено время. Благо в облаке можно в любой момент навесить внешний адрес, поэтому время победил быстро и второй запуск показал сразу на удивление хорошие результаты - все тесты прошли, КРОМЕ **/api/sessions** и **отказоустойчивость 3**

Стало понятно, что Watchdog не сильно поможет, так как Петя умеет вводить Бингу в ступор по щелчку байтом)
Ну что, надо пилить healthchecker, благо /ping  у приложения есть, и I feel bad как раз в том сценарии, когда OOM не умеет его убить, он отдаёт.

Решение немного костыльное, но оно полностью решило все вопросы.
```
#!/bin/sh
while true; do
    if output="$(curl -s http://localhost:3901/ping)"; then
        dt=$(date "+%Y-%m-%d %H-%M-%S")
        #echo "$dt $output"
        if [[ "$output" != "pong" ]]; then
            echo "$dt Restarting bingo service"
            sudo systemctl restart bingo
        fi
    else
        #echo "Error while pinging server"
        sleep 5
    fi
    sleep 1
done
```
Подобное можно было бы сообразить и родными средствами systemd, но я решил оставить время на автоматическое развёртывание, потому что в докере это пришлось бы решать по другому.

Так же замечаю, что пройден пункт "Быстрый старт", хотя приложение стартует совсем не быстро.
Расчехляем tcpdump и находим обращение на 8.8.8.8:80. Сначала просто сделал правило iptables на REJECT и это работало - ускоряло старт, но вспомнил про секретные коды!)

В итоге, два новых правила у iptables, а у меня новый секретный код - **google_dns_is_not_http**.
```
iptables -t nat -A OUTPUT -o eth0 -p tcp --dport 80 -d 8.8.8.8 -j DNAT --to-destination 8.8.8.8:53
iptables -A FORWARD -i eth0 -p tcp -d 8.8.8.8 --dport 53 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
```

Но это ещё не всё - в логах вижу POST обращения Пети на эндпоинт **/** !
Ого, а я там даже не был - плюс ещё один секретный код **index_page_is_awesome**.

tcpdump'ом же собрал и все обращения Пети. Хотелось самому научиться включать разные сценарии у bingo.
Пытался сопоставить по времени с логами приложения, возможно загрузить в БД для более комфортного анализа, но потом решил, что трачу впустую время.

## Тюнинг БД
Ещё один не пройденный пункт - при обращении к /api/sessions к базе делалось сразу три одинаковых жирных запроса, которые в сумме выполнялись 24 секунды, тогда как таймлимит у bingo был 20.

``` sql
SELECT sessions.id, sessions.start_time, customers.id, customers.name, customers.surname, customers.birthday, customers.email, movies.id, movies.name, movies.year, movies.duration FROM sessions INNER JOIN customers ON sessions.customer_id = customers.id INNER JOIN movies ON sessions.movie_id = movies.id
ORDER BY movies.year DESC, movies.name ASC, customers.id, sessions.id DESC LIMIT 100000;
```
Причом запрос был копией запроса к /api/session/{id}, кроме отсутствия фильтра WHERE
```sql
SELECT sessions.id, sessions.start_time, customers.id, customers.name, customers.surname, customers.birthday, customers.email, movies.id, movies.name, movies.year, movies.duration FROM sessions INNER JOIN customers ON sessions.customer_id = customers.id INNER JOIN movies ON sessions.movie_id = movies.id
WHERE sessions.id IN ($1)
ORDER BY movies.year DESC, movies.name ASC, customers.id, sessions.id DESC LIMIT 100000;
```
Выглядит не очень эффективно:
```
                                                QUERY PLAN
----------------------------------------------------------------------------------------------------------
 Limit  (cost=444285.48..501465.72 rows=100000 width=101)
   ->  Nested Loop  (cost=444285.48..3303299.72 rows=5000004 width=101)
         ->  Gather Merge  (cost=444285.06..1026617.92 rows=5000004 width=53)
               Workers Planned: 2
               ->  Sort  (cost=443285.04..448493.37 rows=2083335 width=53)
                     Sort Key: movies.year DESC, movies.name, sessions.customer_id, sessions.id DESC
                     ->  Hash Join  (cost=885.00..82212.20 rows=2083335 width=53)
                           Hash Cond: (sessions.movie_id = movies.id)
                           ->  Parallel Seq Scan on sessions  (cost=0.00..52681.35 rows=2083335 width=24)
                           ->  Hash  (cost=522.22..522.22 rows=29022 width=33)
                                 ->  Seq Scan on movies  (cost=0.00..522.22 rows=29022 width=33)
         ->  Index Scan using customerid_idx on customers  (cost=0.42..0.45 rows=1 width=52)
               Index Cond: (id = sessions.customer_id)
(13 rows)
```
Конечно ж мысли про кэширование, тюнинг базы и прочее меня поглотили и я примерно день потратил на различные ухищрения по настройке постгреса. Было перепробовано множество различных методик, вариантов конфига, увеличение workers и прочего-прочего совмесно с EXPLAIN. Даже делался прогрев кэша)

Но самую главную работу **уже** сделало первоначальное добавление индексов на поля id, остальные изменения были в пределах погрешности измерений.

В итоге сложилось мнение, что проще решить двумя способами - 1-й - нужно ТРИ свободных ядра, чтобы запросы могли выполняться одновременно или поднять db-кластер на минимальных 2-х ядерных конфигах(не зря на лекциях это было). Победила виртуалка с 4 ядрами и переехавшая туда база, перевесив остальные варианты своей простотой.

## Архитектура
После прохождения через все бинго-тернии, оптимальная конфигурация для решения задачи виделась такой - две виртуалки, одна минимальная, на которой фронтом развёрнут **nginx** и за ним, уже **в докерах**, ноды **bingo**.
И на второй, 4-х ядерной, чисто БД.

Такое решение позволило бы легко расширять возможности по нагрузке - **bingo** потребляет совсем немного и памяти, и проца, а жизнь в докере успокоила бы его забагованность (легко убиваются, легко рестартятся/создаются новые/дополнительные).

На реальном проде было бы несложно поднимать дополнительные докеры, а при необходимости и новые виртуалки, полные докеров с бинго. Но при росте нагрузок **nginx** конечно лучше вынести на отдельную виртуалку.

Так же и с БД - с ростом нагрузки поднимаем дополнительные хосты, но по началу просто наращиваем железо.

Если подобное решение раскопировать по гео разнесённым датацентрам и сверху ещё отбалансить round-robin'ом, то можно будет держать серьёзные нагрузки, несмотря на кривое приложение.

## Авторазворачивание.
И тут первые сложности.

Чтобы воплотить архитектуру, описанную выше, нужны более сложные инструменты, чем  docker.
Подозреваю, что **Ansible** справился бы, но изучать его времени особо не было. А настраивать виртуалки скриптами через ssh слишком костыльно, хотя раньше я так и делал.
C докерами дело раньше уже имел, с docker compose ещё нет.
Ну вот и решил хотя бы для себя успеть за 8 часов до дедлайна разобраться и сделать. Ну и в целом всё даже получилось.

Правда конфиги бд и прочих deploy: resources: выбраны примерно наугад, но стенд поднимается и даже выдаёт RPS под нагрузкой. Пете отдать побоялся, потому что закончил за полтора часа до 23:59 и решил не рисковать, чтобы прошлые результаты не потёрлись. А сегодня весь день пишу этот отчёт)

Если Петя ещё будет жить, завтра думаю попробовать и допишу новым файлом результаты.
Заранее напишу в каком - README2.md

## Заключение

Во-первых, огромное спасибо придумщикам и воплотителям этого конкурса, - давно не испытывал подобных эмоций. Очень затягивающее и поглощающее действо получилось. Плюс мощный стимул подтянуть пробелы. Прям искреннее СПАСИБО! 

Во-вторых, спасибо за возможность потрогать Ya.Cloud.

А третье спасибо - за отзывчивость и непринуждённость в чатах. Ваши ответы/советы/помощь очень помогали и настраивали на нужный лад.


p.s. Наверняка что-то забыл, потому что ничего сразу не записывал)








