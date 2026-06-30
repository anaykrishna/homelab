# Validates the rendered compose has the four services and required customizations.
_compose_tmp=$(mktemp -d)
trap 'rm -rf "$_compose_tmp"' RETURN
cp ../config/.env.example "$_compose_tmp/.env.validate"
cp ../config/.env.example "$_compose_tmp/.env"
RENDER=$(docker compose --project-directory "$_compose_tmp" --env-file "$_compose_tmp/.env.validate" -f ../config/docker-compose.yml config 2>/dev/null)
rm -f "$_compose_tmp/.env.validate"

has() { grep -q "$1" <<<"$RENDER" && echo yes || echo no; }

assert_eq "$(has 'container_name: immich_server')"            "yes" "compose has immich_server"
assert_eq "$(has 'container_name: immich_machine_learning')"  "yes" "compose has ML container"
assert_eq "$(has 'container_name: immich_redis')"             "yes" "compose has redis"
assert_eq "$(has 'container_name: immich_postgres')"          "yes" "compose has postgres"
assert_eq "$(grep -c 'restart: always' <<<"$RENDER")"         "4"   "all four services restart: always"
assert_eq "$(has '/photos')"                                  "yes" "UPLOAD_LOCATION resolves to /photos"
