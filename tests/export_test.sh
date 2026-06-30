source ../config/bin/immich-export.sh

assert_eq "$(build_dump_name 20260630-2100)" "immich-db-20260630-2100.sql.gz" "dump name format"
